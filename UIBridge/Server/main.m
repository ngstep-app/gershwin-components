/*
 * Copyright (c) 2026 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import "../Common/UIBridgeProtocol.h"
#import "X11Support.h"
#import "LLDBController.h"

// Simple JSON helper
static id ParseJSON(NSString *input) {
    if (!input) return nil;
    NSData *data = [input dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    if (!data) return nil;
    return [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
}

static void SendJSON(id obj) {
    if (!obj) return;
    @try {
        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:obj options:0 error:&error];
        if (data) {
            NSLog(@"[Server] Serialized JSON successfully, length: %lu", (unsigned long)[data length]);
            // Log raw JSON for debugging (truncated to 16k to avoid noisy logs)
            NSString *jsonStr = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            if (jsonStr) {
                NSString *trunc = ([jsonStr length] > 16384) ? [jsonStr substringToIndex:16384] : jsonStr;
                NSLog(@"[Server] RAW_JSON: %@", trunc);
                [jsonStr release];
            } else {
                NSLog(@"[Server] RAW_JSON: <non-utf8 bytes, length=%lu>", (unsigned long)[data length]);
            }
            NSFileHandle *stdoutHandle = [NSFileHandle fileHandleWithStandardOutput];
            [stdoutHandle writeData:data];
            [stdoutHandle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
            [stdoutHandle synchronizeFile];
            NSLog(@"[Server] Sent JSON to stdout.");
        } else {
            NSLog(@"[Server] JSON Serialization failed: %@", error);
        }
    } @catch (NSException *e) {
        NSLog(@"[Server] EXCEPTION in SendJSON: %@", e);
    }
}

static id<UIBridgeProtocol> ConnectToAgent(int pid) {
    NSString *connName = [NSString stringWithFormat:@"UIBridgeAgent%d", pid];
    NSLog(@"[Server] Connecting to %@", connName);
    id proxy = [NSConnection rootProxyForConnectionWithRegisteredName:connName host:nil];
    if (proxy) {
        [(NSDistantObject *)proxy setProtocolForProxy:@protocol(UIBridgeProtocol)];
    } else {
        NSLog(@"[Server] Failed to get proxy for %@", connName);
    }
    return proxy;
}


static int LaunchApp(NSString *appPath) {
    NSTask *task = [[NSTask alloc] init];
    
    NSString *appName = [[appPath lastPathComponent] stringByDeletingPathExtension];
    NSString *executable = [appPath stringByAppendingPathComponent:appName];
    [task setLaunchPath:executable];
    
    // Set environment to inject agent
    NSMutableDictionary *env = [[[NSProcessInfo processInfo] environment] mutableCopy];
    
    // Resolve absolute path to the agent dylib relative to the server's own directory
    NSString *serverPath = [[NSBundle mainBundle] executablePath];
    if (!serverPath) serverPath = [[NSProcessInfo processInfo] arguments][0];
    
    NSString *baseDir = [serverPath stringByDeletingLastPathComponent];
    // Preferred agent path: use GNUSTEP_SYSTEM_LIBRARIES if set, otherwise fall back to conventional locations
    const char *gsLibs = getenv("GNUSTEP_SYSTEM_LIBRARIES");
    NSString *systemLibsDir = gsLibs ? [NSString stringWithUTF8String:gsLibs] : @"/System/Library/Libraries";
    NSArray *candidatePaths = @[
        [systemLibsDir stringByAppendingPathComponent:@"libUIBridgeAgent.so"],
        [[baseDir stringByAppendingPathComponent:@"../../Agent/obj/libUIBridgeAgent.so"] stringByStandardizingPath],
        @"/usr/lib/libUIBridgeAgent.so",
        @"/usr/local/lib/libUIBridgeAgent.so"
    ];
    NSString *agentPath = nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    for (NSString *p in candidatePaths) {
        if ([fm fileExistsAtPath:p]) {
            agentPath = p;
            break;
        }
    }
    if (!agentPath) {
        // Fallback to the build-relative path (second candidate) and warn
        agentPath = [candidatePaths[1] copy];
        NSLog(@"[Server] WARNING: Agent library not found in standard locations; will attempt to use: %@", agentPath);
    }
    NSLog(@"[Server] Injecting agent from: %@", agentPath);
    env[@"LD_PRELOAD"] = agentPath;
    env[@"UIBRIDGE_TARGET"] = appName;    
    
    [task setEnvironment:env];
    [task launch];
    
    int pid = [task processIdentifier];
    NSString *connName = [NSString stringWithFormat:@"UIBridgeAgent%d", pid];
    NSLog(@"[Server] Waiting for agent registration: %@", connName);
    
    // Poll for registration (up to 15 seconds)
    BOOL registered = NO;
    for (int i = 0; i < 150; i++) {
        id proxy = [NSConnection rootProxyForConnectionWithRegisteredName:connName host:nil];
        if (proxy) {
            registered = YES;
            NSLog(@"[Server] Agent registration confirmed for PID %d", pid);
            break;
        }
        [NSThread sleepForTimeInterval:0.1];
    }
    
    if (!registered) {
        NSLog(@"[Server] WARNING: Agent registration timed out for %@", connName);
    }
    
    return pid;
}

static void RedirectLogs(void) {
    const char *logPath = "/tmp/uibridge.log";
    freopen(logPath, "a", stderr);
    NSLog(@"[Server] --- UIBridge Server Session Start ---");
}

@interface BridgeServer : NSObject
@property (assign) int currentPID;
- (void)checkInput:(NSTimer *)timer;
@end

@implementation BridgeServer

- (void)checkInput:(NSTimer *)timer {
    static BOOL hadData = NO;
    NSData *data = [[NSFileHandle fileHandleWithStandardInput] availableData];
    if ([data length] > 0) {
        hadData = YES;
        NSString *chunk = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"[Server] Read chunk: %@", chunk);
        NSArray *lines = [chunk componentsSeparatedByString:@"\n"];
        
        for (NSString *line in lines) {
            NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            if ([trimmed length] == 0) continue;
            
            NSDictionary *json = ParseJSON(trimmed);
            if (!json) continue;
            
            [self processRequest:json];
        }
    } else if (hadData) {
        // EOF after having data
        exit(0);
    }
}

- (void)processRequest:(NSDictionary *)json {
    id reqID = json[@"id"];
    NSString *method = json[@"method"];
    NSDictionary *params = json[@"params"];

    NSLog(@"[Server] Processing request: method=%@, id=%@", method, reqID);

    id result = nil;
    NSString *errorMsg = nil;
    int errorCode = -32603;
    BOOL hasError = NO;

    @try {
        if (!method || !reqID) {
            hasError = YES;
            errorMsg = @"Invalid Request: missing 'method' or 'id'";
            errorCode = -32600;
        } else if ([method isEqualToString:@"initialize"]) {
        result = @{
            @"protocolVersion": params[@"protocolVersion"] ?: @"2024-11-05",
            @"capabilities": @{
                @"tools": @{},
                @"resources": @{},
                @"prompts": @{}
            },
            @"serverInfo": @{@"name": @"uibridge", @"version": @"1.0.0"}
        };
    } else if ([method isEqualToString:@"tools/list"] || [method isEqualToString:@"list_tools"]) {
        // Canonical MCP structure for tools: wrap success in content schema
        id contentSchema = @{
            @"type": @"object",
            @"properties": @{
                @"content": @{
                    @"type": @"array",
                    @"items": @{
                        @"type": @"object",
                        @"properties": @{
                            @"type": @{@"type": @"string", @"enum": @[@"json", @"text"]},
                            @"json": @{@"type": @"object"},
                            @"text": @{@"type": @"string"}
                        }
                    }
                }
            }
        };

        result = @{
            @"tools": @[
                @{@"name": @"launch_app", @"description": @"Launch a GNUstep app with UIBridge agent injected. Returns when agent registers.", @"inputSchema": @{@"type": @"object", @"properties": @{@"app_path": @{@"type": @"string"}}}, @"outputSchema": contentSchema},
                @{@"name": @"list_apps", @"description": @"List available GNUstep applications.", @"inputSchema": @{@"type": @"object", @"properties": @{}}, @"outputSchema": contentSchema},
                @{@"name": @"list_files", @"description": @"List files in a directory.", @"inputSchema": @{@"type": @"object", @"properties": @{@"path": @{@"type": @"string"}}}, @"outputSchema": contentSchema},
                @{@"name": @"read_file_content", @"description": @"Read the content of a file.", @"inputSchema": @{@"type": @"object", @"properties": @{@"path": @{@"type": @"string"}}}, @"outputSchema": contentSchema},
                @{@"name": @"get_root", @"description": @"Get root objects (NSApp, windows) from the app.", @"inputSchema": @{@"type": @"object", @"properties": @{}}, @"outputSchema": contentSchema},
                @{@"name": @"get_object_details", @"description": @"Inspect an object's properties.", @"inputSchema": @{@"type": @"object", @"properties": @{@"object_id": @{@"type": @"string"}}}, @"outputSchema": contentSchema},
                @{@"name": @"invoke_selector", @"description": @"Invoke a selector on an object.", @"inputSchema": @{@"type": @"object", @"properties": @{@"object_id": @{@"type": @"string"}, @"selector": @{@"type": @"string"}, @"args": @{@"type": @"array", @"items": @{}}}}, @"outputSchema": contentSchema},
                // Menu Tools
                @{@"name": @"list_menus", @"description": @"List all menus in the app.", @"inputSchema": @{@"type": @"object", @"properties": @{}}, @"outputSchema": contentSchema},
                @{@"name": @"invoke_menu_item", @"description": @"Invoke a menu item by object_id.", @"inputSchema": @{@"type": @"object", @"properties": @{@"object_id": @{@"type": @"string"}}}, @"outputSchema": contentSchema},
                // X11 Tools
                @{@"name": @"x11_list_windows", @"description": @"List all X11 windows.", @"inputSchema": @{@"type": @"object", @"properties": @{}}, @"outputSchema": contentSchema},
                @{@"name": @"x11_window_info", @"description": @"Get details for an X11 window.", @"inputSchema": @{@"type": @"object", @"properties": @{@"xid": @{@"type": @"integer"}}}, @"outputSchema": contentSchema},
                @{@"name": @"x11_mouse_move", @"description": @"Move mouse cursor.", @"inputSchema": @{@"type": @"object", @"properties": @{@"x": @{@"type": @"integer"}, @"y": @{@"type": @"integer"}}}, @"outputSchema": contentSchema},
                @{@"name": @"x11_click", @"description": @"Click mouse button.", @"inputSchema": @{@"type": @"object", @"properties": @{@"button": @{@"type": @"integer", @"description": @"1=left, 2=middle, 3=right"}}}, @"outputSchema": contentSchema},
                @{@"name": @"x11_type", @"description": @"Type a string.", @"inputSchema": @{@"type": @"object", @"properties": @{@"text": @{@"type": @"string"}}}, @"outputSchema": contentSchema},
                // LLDB Tools
                @{@"name": @"lldb_exec", @"description": @"Execute an LLDB command on the attached app.", @"inputSchema": @{@"type": @"object", @"properties": @{@"command": @{@"type": @"string"}}}, @"outputSchema": contentSchema}
            ]
        };
    } else if ([method isEqualToString:@"resources/list"] || [method isEqualToString:@"list_resources"]) {
        result = @{@"resources": @[]};
    } else if ([method isEqualToString:@"prompts/list"] || [method isEqualToString:@"list_prompts"]) {
        result = @{@"prompts": @[]};
    } else if ([method isEqualToString:@"notifications/initialized"]) {
        // Notification, no result needed
        return;
    } else {
        // Handle tool calls which might come wrapped in tools/call
        NSDictionary *callParams = params;
        NSString *toolName = method;
        
        if ([method isEqualToString:@"tools/call"]) {
            toolName = params[@"name"];
            callParams = params[@"arguments"];
        }
        
        if ([toolName isEqualToString:@"launch_app"]) {
            NSString *path = callParams[@"app_path"];
            if (path) {
                self.currentPID = LaunchApp(path);
                if (self.currentPID > 0) {
                    result = @{@"pid": @(self.currentPID), @"status": @"launched"};
                } else {
                     errorMsg = @"Failed to launch";
                }
            } else {
                errorMsg = @"Missing app_path";
            }
        } else if ([toolName isEqualToString:@"list_apps"]) {
            NSFileManager *fm = [NSFileManager defaultManager];
            NSArray *paths = NSSearchPathForDirectoriesInDomains(NSAllApplicationsDirectory, NSAllDomainsMask, YES);
            NSMutableArray *apps = [NSMutableArray array];
            for (NSString *path in paths) {
                NSError *error = nil;
                NSArray *contents = [fm contentsOfDirectoryAtPath:path error:&error];
                if (contents) {
                    for (NSString *item in contents) {
                        if ([item hasSuffix:@".app"]) {
                            NSString *fullPath = [path stringByAppendingPathComponent:item];
                            NSString *executable = [item stringByDeletingPathExtension];
                            NSString *execPath = [[fullPath stringByAppendingPathComponent:executable] stringByStandardizingPath];
                            [apps addObject:@{@"name": item, @"path": fullPath, @"executable": execPath}];
                        }
                    }
                }
            }
            result = @{@"apps": apps};
        } else if ([toolName isEqualToString:@"list_files"]) {
            NSString *path = callParams[@"path"];
            if (!path) path = @".";
            NSError *error = nil;
            NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:path error:&error];
            if (contents) {
                result = @{@"contents": contents};
            } else {
                errorMsg = [NSString stringWithFormat:@"Failed to list directory: %@", error];
            }
        } else if ([toolName isEqualToString:@"read_file_content"]) {
            NSString *path = callParams[@"path"];
            if (path) {
                NSError *error = nil;
                NSString *content = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&error];
                if (content) {
                    result = @{@"content": content};
                } else {
                    errorMsg = [NSString stringWithFormat:@"Failed to read file: %@", error];
                }
            } else {
                errorMsg = @"Missing path";
            }
        } else if ([toolName isEqualToString:@"x11_list_windows"]) {
            result = @{@"windows": [X11Support windowList]};
        } else if ([toolName isEqualToString:@"x11_window_info"]) {
            NSNumber *xid = callParams[@"xid"];
            if (xid) {
                NSDictionary *info = [X11Support windowInfo:[xid unsignedLongValue]];
                if (info) result = info;
                else errorMsg = @"Window not found or invalid XID";
            } else {
                errorMsg = @"Missing xid";
            }
        } else if ([toolName isEqualToString:@"x11_mouse_move"]) {
            NSNumber *x = callParams[@"x"];
            NSNumber *y = callParams[@"y"];
            if (x && y) {
                [X11Support simulateMouseMoveTo:NSMakePoint([x doubleValue], [y doubleValue])];
                result = @{@"status": @"ok"};
            } else {
                errorMsg = @"Missing x or y";
            }
        } else if ([toolName isEqualToString:@"x11_click"]) {
            NSNumber *btn = callParams[@"button"] ?: @1;
            [X11Support simulateClick:[btn intValue]];
            result = @{@"status": @"ok"};
        } else if ([toolName isEqualToString:@"x11_type"]) {
            NSString *text = callParams[@"text"];
            if (text) {
                [X11Support simulateKeyStroke:text];
                result = @{@"status": @"ok"};
            } else {
                errorMsg = @"Missing text";
            }
        } else if ([toolName isEqualToString:@"lldb_exec"]) {
            if (self.currentPID == 0) {
                errorMsg = @"No app running. Call launch_app first.";
            } else {
                NSString *cmd = callParams[@"command"];
                if (cmd) {
                     // Warning: this is slow because it attaches/detaches every time.
                    result = @{@"output": [LLDBController runCommand:cmd forPID:self.currentPID]};
                } else {
                    errorMsg = @"Missing command";
                }
            }
        } else if (self.currentPID == 0 && ![toolName isEqualToString:@"launch_app"]) {
            errorMsg = @"No app running. Call launch_app first.";
        } else {
            id<UIBridgeProtocol> agent = ConnectToAgent(self.currentPID);
            if (!agent) {
                errorMsg = @"Could not connect to Agent";
            } else {
                @try {
                    id jsonResult = nil; // may be NSString, NSData, NSDictionary, or NSArray
                    if ([toolName isEqualToString:@"get_root"]) {
                        NSLog(@"[Server] Requesting agent root objects...");
                        if ([agent respondsToSelector:@selector(rootObjectsJSON)]) {
                            jsonResult = [agent rootObjectsJSON];
                        } else {
                            jsonResult = [agent rootObjects];
                        }
                    } else if ([toolName isEqualToString:@"get_object_details"]) {
                        if ([agent respondsToSelector:@selector(detailsForObjectJSON:)]) {
                            jsonResult = [agent detailsForObjectJSON:callParams[@"object_id"]];
                        } else {
                            jsonResult = [agent detailsForObject:callParams[@"object_id"]];
                        }
                    } else if ([toolName isEqualToString:@"invoke_selector"]) {
                        if ([agent respondsToSelector:@selector(invokeSelectorJSON:onObject:withArgs:)]) {
                            jsonResult = [agent invokeSelectorJSON:callParams[@"selector"] onObject:callParams[@"object_id"] withArgs:callParams[@"args"]];
                        } else {
                            jsonResult = [agent invokeSelector:callParams[@"selector"] onObject:callParams[@"object_id"] withArgs:callParams[@"args"]];
                        }
                    } else if ([toolName isEqualToString:@"list_menus"]) {
                        // Call listMenus via DO proxy (agent)
                        if ([agent respondsToSelector:@selector(listMenus)]) {
                            NSArray *menus = [agent performSelector:@selector(listMenus)];
                            result = menus;
                        } else if ([agent respondsToSelector:@selector(listMenusJSON)]) {
                            NSString *menusJSON = [agent performSelector:@selector(listMenusJSON)];
                            result = ParseJSON(menusJSON);
                        } else {
                            errorMsg = @"Agent does not support menu listing";
                        }
                    } else if ([toolName isEqualToString:@"invoke_menu_item"]) {
                        // Call invokeMenuItem via DO proxy (agent)
                        BOOL ok = NO;
                        if ([agent respondsToSelector:@selector(invokeMenuItem:)]) {
                            ok = [agent invokeMenuItem:callParams[@"object_id"]];
                        }
                        result = @{ @"status": ok ? @"invoked" : @"failed" };
                    } else {
                        errorMsg = [NSString stringWithFormat:@"Unknown tool: %@", toolName];
                    }
                    if (jsonResult) {
                        // Defensive: agent may return NSString (JSON), NSData (raw bytes),
                        // or even already-parsed NSDictionary/NSArray in some DO implementations.
                        NSLog(@"[Server] Agent returned object of class: %@", NSStringFromClass([jsonResult class]));
                        if ([jsonResult isKindOfClass:[NSString class]]) {
                            result = ParseJSON(jsonResult);
                        } else if ([jsonResult isKindOfClass:[NSData class]]) {
                            NSLog(@"[Server] Agent returned NSData — attempting to decode as UTF-8 JSON string");
                            NSString *s = [[NSString alloc] initWithData:jsonResult encoding:NSUTF8StringEncoding];
                            if (s) {
                                result = ParseJSON(s);
                            } else {
                                NSLog(@"[Server] Failed to decode agent NSData as UTF-8");
                                result = @{ @"error": @"Agent returned non-UTF8 NSData" };
                            }
                            [s release];
                        } else if ([jsonResult isKindOfClass:[NSDictionary class]] || [jsonResult isKindOfClass:[NSArray class]]) {
                            result = jsonResult;
                        } else if (jsonResult == [NSNull null] || jsonResult == nil) {
                            result = nil;
                        } else {
                            // Fallback: try to stringify and parse
                            NSLog(@"[Server] Agent returned unexpected type — using description() as fallback");
                            NSString *desc = [jsonResult description];
                            result = ParseJSON(desc);
                        }
                    }
                } @catch (NSException *e) {
                    errorMsg = [NSString stringWithFormat:@"Exception: %@", e];
                }
            }
        }
    }
    } @catch (NSException *e) {
        hasError = YES;
        errorMsg = [NSString stringWithFormat:@"Internal error: %@", e];
        errorCode = -32603;
    }

    NSLog(@"[Server] Constructing response...");
    NSMutableDictionary *resp = [NSMutableDictionary dictionary];
    resp[@"jsonrpc"] = @"2.0";
    resp[@"id"] = reqID ?: [NSNull null];

    if (hasError || errorMsg) {
        if ([method isEqualToString:@"tools/call"]) {
             resp[@"result"] = @{
                 @"content": @[@{ @"type": @"text", @"text": [NSString stringWithFormat:@"Error: %@", errorMsg] }],
                 @"isError": @YES
             };
        } else {
             resp[@"error"] = @{@"code": @(errorCode), @"message": errorMsg ?: @"Unknown error"};
        }
    } else {
        // Ensure result is JSON-safe
        if (result && !([result isKindOfClass:[NSDictionary class]] ||
                       [result isKindOfClass:[NSArray class]] ||
                       [result isKindOfClass:[NSString class]] ||
                       [result isKindOfClass:[NSNumber class]] ||
                       result == [NSNull null])) {
            result = [result description];
        }

        if ([method isEqualToString:@"tools/call"]) {
            // VS Code / MCP expectation: wrap in content array
            id contentItem = nil;
            if (result && ([result isKindOfClass:[NSDictionary class]] || [result isKindOfClass:[NSArray class]])) {
                contentItem = @{ @"type": @"json", @"json": result };
            } else if (result) {
                contentItem = @{ @"type": @"text", @"text": [result description] };
            } else {
                contentItem = @{ @"type": @"text", @"text": @"ok" };
            }
            resp[@"result"] = @{
                @"content": @[contentItem],
                @"isError": @NO
            };
        } else {
            resp[@"result"] = result ?: @{};
        }
    }
    NSLog(@"[Server] Calling SendJSON...");
    SendJSON(resp);
    NSLog(@"[Server] processRequest finished.");
}

@end

int main(int argc, const char *argv[]) {
    setenv("GNUSTEP_SYSTEM_ROOT", "/System", 1);
    
    // Set LD_LIBRARY_PATH for GNUstep libraries
    const char *ldpath = getenv("LD_LIBRARY_PATH");
    NSString *ldpathStr = ldpath ? [NSString stringWithUTF8String:ldpath] : @"";
    NSString *newLdPath = [NSString stringWithFormat:@"/home/devuan/gershwin-build/repos/libs-base/Source/obj:/home/devuan/gershwin-build/repos/libs-gui/Source/obj:/home/devuan/gershwin-build/repos/UIBridge/Agent/obj%@%@", ldpath ? @":" : @"", ldpathStr];
    setenv("LD_LIBRARY_PATH", [newLdPath UTF8String], 1);
    
    // Unbuffer stdout
    setbuf(stdout, NULL);
    
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    RedirectLogs();
    
    BridgeServer *server = [[BridgeServer alloc] init];

    // Use timer to poll for input. The scheduled timer is retained by the run loop so
    // there is no need to keep a local reference here.
    [NSTimer scheduledTimerWithTimeInterval:0.001 target:server selector:@selector(checkInput:) userInfo:nil repeats:YES];
    
    // [[NSNotificationCenter defaultCenter] addObserver:server 
    //                                          selector:@selector(handleInput:) 
    //                                              name:NSFileHandleReadCompletionNotification 
    //                                            object:inputHandle];
    
    // [inputHandle readInBackgroundAndNotify];
    
    NSLog(@"[Server] Starting RunLoop...");
    [[NSRunLoop currentRunLoop] run];
    
    [pool release];
    return 0;
}

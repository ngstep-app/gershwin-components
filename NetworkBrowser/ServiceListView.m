/*
 * Copyright (c) 2025 Simon Peter
 *
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import "ServiceListView.h"
#import "ServiceDetailsView.h"

@implementation ServiceListView

- (id)initWithFrame:(NSRect)frame
{
  self = [super initWithFrame: frame];
  if (self)
    {
      services = [[NSMutableArray alloc] init];
      detailsView = nil;
      
      /* Create scroll view */
      scrollView = [[NSScrollView alloc] initWithFrame: frame];
      [scrollView setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
      [scrollView setHasVerticalScroller: YES];
      [scrollView setHasHorizontalScroller: NO];
      
      /* Create table view */
      NSRect tableFrame = NSMakeRect(0, 0, frame.size.width, frame.size.height);
      tableView = [[NSTableView alloc] initWithFrame: tableFrame];
      [tableView setDataSource: self];
      [tableView setDelegate: self];
      [tableView setAllowsEmptySelection: YES];
      [tableView setAllowsColumnReordering: NO];
      [tableView setAllowsColumnResizing: YES];
      [tableView setAllowsMultipleSelection: NO];
      
      /* Add column */
      NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier: @"name"];
      [[column headerCell] setStringValue: @"Service Name"];
      [column setWidth: frame.size.width - 20];
      [tableView addTableColumn: column];
      RELEASE(column);
      
      [scrollView setDocumentView: tableView];
      [self addSubview: scrollView];
    }
  return self;
}

- (void)dealloc
{
  RELEASE(services);
  RELEASE(scrollView);
  RELEASE(tableView);
  [super dealloc];
}

- (void)setDetailsView:(ServiceDetailsView *)view
{
  detailsView = view;
}

- (void)setSelectionDelegate:(id)delegate
{
  selectionDelegate = delegate;
}

- (void)addService:(NSNetService *)service
{
  if (![services containsObject: service])
    {
      [services addObject: service];
      [tableView reloadData];
    }
}

- (void)removeService:(NSNetService *)service
{
  [services removeObject: service];
  [tableView reloadData];
}

- (void)clearServices
{
  [services removeAllObjects];
  [tableView reloadData];
}

- (NSArray *)services
{
  return [NSArray arrayWithArray: services];
}

- (NSNetService *)selectedService
{
  NSInteger sel = [tableView selectedRow];
  if (sel >= 0 && sel < (NSInteger)[services count])
    return [services objectAtIndex: sel];
  return nil;
}

/* NSTableViewDataSource methods */

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
  return [services count];
}

- (id)tableView:(NSTableView *)tableView 
    objectValueForTableColumn:(NSTableColumn *)tableColumn 
    row:(NSInteger)row
{
  NSNetService *service = [services objectAtIndex: row];
  if ([[tableColumn identifier] isEqual: @"name"])
    {
      return [service name];
    }
  return nil;
}

/* NSTableViewDelegate methods */

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
  NSInteger selectedRow = [tableView selectedRow];
  
  if (selectedRow >= 0 && selectedRow < (NSInteger)[services count])
    {
      NSNetService *service = [services objectAtIndex: selectedRow];
      if (detailsView)
        {
          [detailsView displayService: service];
        }
    }
  else
    {
      if (detailsView)
        {
          [detailsView clear];
        }
    }

  if (selectionDelegate && [selectionDelegate respondsToSelector:@selector(serviceListViewSelectionDidChange:)])
    {
      [selectionDelegate serviceListViewSelectionDidChange: self];
    }
}

@end

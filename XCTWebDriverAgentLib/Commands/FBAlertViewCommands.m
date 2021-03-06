/**
 * Copyright (c) 2015-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "FBAlertViewCommands.h"

#import <XCTest/XCUICoordinate.h>

#import "FBFindElementCommands.h"
#import "FBRouteRequest.h"
#import "FBXCTSession.h"
#import "XCAXClient_iOS.h"
#import "XCElementSnapshot+Helpers.h"
#import "XCElementSnapshot-Hitpoint.h"
#import "XCElementSnapshot.h"
#import "XCTestManager_ManagerInterface-Protocol.h"
#import "XCUIApplication.h"
#import "XCUICoordinate.h"
#import "XCUIElement+WebDriverAttributes.h"
#import "XCUIElement.h"
#import "XCUIElementQuery.h"

NSString *const FBUAlertObstructingElementException = @"FBUAlertObstructingElementException";

@implementation FBAlertViewCommands

#pragma mark - <FBCommandHandler>

+ (NSArray *)routes
{
  return
  @[
    [[FBRoute GET:@"/session/:sessionID/alert_text"] respond:^ id<FBResponsePayload> (FBRouteRequest *request) {
      FBXCTSession *session = (FBXCTSession *)request.session;
      NSString *alertText = [self.class currentAlertTextWithApplication:session.application];
      if (!alertText) {
        return FBResponseDictionaryWithStatus(FBCommandStatusNoSuchElement, @"unable to find an alert");
      }
      return FBResponseDictionaryWithStatus(FBCommandStatusNoError, alertText);
    }],
    [[FBRoute POST:@"/session/:sessionID/accept_alert"] respond:^ id<FBResponsePayload> (FBRouteRequest *request) {
      FBXCTSession *session = (FBXCTSession *)request.session;
      if (![self.class acceptAlertWithApplication:session.application]) {
        return FBResponseDictionaryWithStatus(FBCommandStatusNoSuchElement, @"unable to find an alert");
      }
      return FBResponseDictionaryWithOK();
    }],
    [[FBRoute POST:@"/session/:sessionID/dismiss_alert"] respond:^ id<FBResponsePayload> (FBRouteRequest *request) {
      FBXCTSession *session = (FBXCTSession *)request.session;
      if (![self.class dismissAlertWithApplication:session.application]) {
        return FBResponseDictionaryWithStatus(FBCommandStatusNoSuchElement, @"unable to find an alert");
      }
      return FBResponseDictionaryWithOK();
    }],
  ];
}

+ (void)ensureElementIsNotObstructedByAlertView:(XCUIElement *)element
{
  [self ensureElementIsNotObstructedByAlertView:element alert:[self applicationAlertWithApplication:element.application]];
}

+ (void)ensureElementIsNotObstructedByAlertView:(XCUIElement *)element alert:(XCUIElement *)alert
{
  if (![self isElementObstructedByAlertView:element alert:alert]) {
    return;
  }
  [self throwRequestedItemObstructedByAlertException];
}

+ (BOOL)isElementObstructedByAlertView:(XCUIElement *)element alert:(XCUIElement *)alert
{
  if (!alert.exists) {
    return NO;
  }
  [alert resolve];
  [element resolve];
  if ([alert.lastSnapshot _isAncestorOfElement:element.lastSnapshot]) {
    return NO;
  }
  if ([alert.lastSnapshot _matchesElement:element.lastSnapshot]) {
    return NO;
  }
  return YES;
}

+ (NSArray *)filterElementsObstructedByAlertView:(NSArray *)elements
{
  XCUIElement *element = elements.lastObject;
  if (!element) {
    return elements;
  }
  XCUIElement *alert = [self applicationAlertWithApplication:element.application];

  NSMutableArray *elementBox = [NSMutableArray array];
  for (XCUIElement *iElement in elements) {
    if ([FBAlertViewCommands isElementObstructedByAlertView:iElement alert:alert]) {
      continue;
    }
    [elementBox addObject:iElement];
  }
  if (elementBox.count == 0 && elements.count != 0) {
    [self throwRequestedItemObstructedByAlertException];
  }
  return elementBox.copy;
}

+ (void)throwRequestedItemObstructedByAlertException
{
  @throw [NSException exceptionWithName:FBUAlertObstructingElementException reason:@"Requested element is obstructed by alert or action sheet" userInfo:@{}];
}


#pragma mark - Helpers

+ (id)currentAlertTextWithApplication:(XCUIApplication *)application
{
  XCElementSnapshot *alertSnapshot = [self alertSnapshotWithApplication:application];
  if (!alertSnapshot) {
    return nil;
  }
  NSArray<XCElementSnapshot *> *staticTexts = [alertSnapshot fb_descendantsMatchingType:XCUIElementTypeStaticText];
  NSString *text = [staticTexts.lastObject wdLabel];
  if (!text) {
    return [NSNull null];
  }
  return text;
}

+ (BOOL)acceptAlertWithApplication:(XCUIApplication *)application
{
  XCElementSnapshot *alertSnapshot = [self alertSnapshotWithApplication:application];
  NSArray<XCElementSnapshot *> *buttons = [alertSnapshot fb_descendantsMatchingType:XCUIElementTypeButton];

  XCElementSnapshot *defaultButton;
  if (alertSnapshot.elementType == XCUIElementTypeAlert) {
    defaultButton = buttons.lastObject;
  } else {
    defaultButton = buttons.firstObject;
  }
  if (!defaultButton) {
    return NO;
  }
  XCUICoordinate *appCoordinate = [application coordinateWithNormalizedOffset:CGVectorMake(0, 0)];
  XCUICoordinate *coordinate = [[XCUICoordinate alloc] initWithCoordinate:appCoordinate pointsOffset:CGVectorMake(defaultButton.hitPoint.x, defaultButton.hitPoint.y)];
  [coordinate tap];
  return YES;
}

+ (BOOL)dismissAlertWithApplication:(XCUIApplication *)application
{
  XCElementSnapshot *cancelButton;
  XCElementSnapshot *alertSnapshot = [self alertSnapshotWithApplication:application];
  NSArray<XCElementSnapshot *> *buttons = [alertSnapshot fb_descendantsMatchingType:XCUIElementTypeButton];

  if (alertSnapshot.elementType == XCUIElementTypeAlert) {
    cancelButton = buttons.firstObject;
  } else {
    alertSnapshot = buttons.lastObject;
  }
  if (!cancelButton) {
    return NO;
  }
  XCUICoordinate *appCoordinate = [application coordinateWithNormalizedOffset:CGVectorMake(0, 0)];
  XCUICoordinate *coordinate = [[XCUICoordinate alloc] initWithCoordinate:appCoordinate pointsOffset:CGVectorMake(cancelButton.hitPoint.x, cancelButton.hitPoint.y)];
  [coordinate tap];
  return YES;
}

+ (XCUIElement *)applicationAlertWithApplication:(XCUIApplication *)application
{
  XCUIElement *alert = application.alerts.element;
  if (!alert.exists) {
    alert = application.sheets.element;
  }
  return alert;
}

+ (XCElementSnapshot *)alertSnapshotWithApplication:(XCUIApplication *)application
{
  XCUIElement *alert = [self applicationAlertWithApplication:application];
  if (alert.exists) {
    [alert resolve];
    return alert.lastSnapshot;
  }

  NSError *error;
  XCUICoordinate *coordinate = [application coordinateWithNormalizedOffset:CGVectorMake(0.5, 0.5)];
  XCAccessibilityElement *accessibilityElement = [[XCAXClient_iOS sharedClient] elementAtPoint:coordinate.screenPoint error:&error];
  XCElementSnapshot *alertSnapshot;

  XCElementSnapshot *snapshot = [XCElementSnapshot fb_snapshotForAccessibilityElement:accessibilityElement];
  while (snapshot.parentAccessibilityElement) {
    if (snapshot.elementType == XCUIElementTypeAlert) {
      alertSnapshot = snapshot;
      break;
    }
    snapshot = [XCElementSnapshot fb_snapshotForAccessibilityElement:snapshot.parentAccessibilityElement];
  }
  return alertSnapshot;
}

@end

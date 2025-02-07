//
// Copyright 2014 Facebook
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "SimulatorWrapperXcode6.h"

#import "SimDevice.h"
#import "SimDeviceSet.h"
#import "SimDeviceType.h"
#import "SimRuntime.h"
#import "SimulatorInfo.h"
#import "SimulatorLauncher.h"
#import "SimulatorWrapperInternal.h"
#import "XCToolUtil.h"

@implementation SimulatorWrapperXcode6

#pragma mark -
#pragma mark Internal

+ (DTiPhoneSimulatorSessionConfig *)sessionConfigForRunningTestsOnSimulator:(SimulatorInfo *)simInfo
                                                      applicationLaunchArgs:(NSArray *)launchArgs
                                               applicationLaunchEnvironment:(NSDictionary *)launchEnvironment
                                                                 outputPath:(NSString *)outputPath
{
  DTiPhoneSimulatorSessionConfig *sessionConfig = [SimulatorWrapper sessionConfigForRunningTestsOnSimulator:simInfo applicationLaunchArgs:launchArgs applicationLaunchEnvironment:launchEnvironment outputPath:outputPath];

  [sessionConfig setDevice:[simInfo simulatedDevice]];
  [sessionConfig setRuntime:[simInfo simulatedRuntime]];

  return sessionConfig;
}

#pragma mark -
#pragma mark Helpers

+ (BOOL)prepareSimulatorWithSimulatorInfo:(SimulatorInfo *)simInfo
                                    error:(NSError **)error
{
  if (![simInfo simulatedDevice].available) {
    NSString *errorDesc = [NSString stringWithFormat: @"Simulator '%@' is not available", [simInfo simulatedDevice].name];
    if (error) {
      *error = [NSError errorWithDomain:@"com.apple.iOSSimulator"
                                   code:0
                               userInfo:@{NSLocalizedDescriptionKey: errorDesc}];
    }
    return NO;
  }

  NSURL *iOSSimulatorURL = nil;
  if (ToolchainIsXcode7OrBetter()) {
    iOSSimulatorURL = [NSURL fileURLWithPath:[NSString pathWithComponents:@[XcodeDeveloperDirPath(), @"Applications/Simulator.app"]]];
  } else {
    iOSSimulatorURL = [NSURL fileURLWithPath:[NSString pathWithComponents:@[XcodeDeveloperDirPath(), @"Applications/iOS Simulator.app"]]];
  }
  NSDictionary *configuration = @{NSWorkspaceLaunchConfigurationArguments: @[@"-CurrentDeviceUDID", [[[simInfo simulatedDevice] UDID] UUIDString]]};
  NSError *launchError = nil;
  NSRunningApplication *app = [[NSWorkspace sharedWorkspace] launchApplicationAtURL:iOSSimulatorURL
                                                                            options:NSWorkspaceLaunchAsync | NSWorkspaceLaunchWithoutActivation | NSWorkspaceLaunchAndHide
                                                                      configuration:configuration
                                                                              error:&launchError];
  if (!app) {
    NSString *errorDesc = [NSString stringWithFormat: @"iOS Simulator app wasn't launched at path \"%@\" with configuration: %@. Error: %@", [iOSSimulatorURL path], configuration, launchError];
    if (error) {
      *error = [NSError errorWithDomain:@"com.apple.iOSSimulator"
                                   code:0
                               userInfo:@{NSLocalizedDescriptionKey: errorDesc}];
    }
    return NO;
  }

  int attempts = 30;
  while ([[simInfo simulatedDevice] state] != SimDeviceStateBooted && attempts > 0) {
    [NSThread sleepForTimeInterval:0.1];
    --attempts;
  }

  return attempts > 0;
}

#pragma mark -
#pragma mark Main Methods

+ (BOOL)uninstallTestHostBundleID:(NSString *)testHostBundleID
                    simulatorInfo:(SimulatorInfo *)simInfo
                        reporters:(NSArray *)reporters
                            error:(NSString **)error
{
  NSError *localError = nil;
  SimDevice *device = [simInfo simulatedDevice];

  if (![self prepareSimulatorWithSimulatorInfo:simInfo error:&localError]) {
    *error = [NSString stringWithFormat:
              @"Simulator '%@' was not prepared: %@",
              [simInfo simulatedDevice].name, localError.localizedDescription ?: @"Failed for unknown reason."];
    return NO;
  }

  BOOL uninstalled = ![device applicationIsInstalled:testHostBundleID type:nil error:&localError];
  if (!uninstalled) {
    uninstalled = [device uninstallApplication:testHostBundleID
                                   withOptions:nil
                                         error:&localError];
  }

  if (!uninstalled) {
    *error = [NSString stringWithFormat:
              @"Failed to uninstall the test host app '%@' "
              @"before running tests: %@",
              testHostBundleID, localError.localizedDescription ?: @"Failed for unknown reason."];
  }
  return uninstalled;
}

+ (BOOL)installTestHostBundleID:(NSString *)testHostBundleID
                 fromBundlePath:(NSString *)testHostBundlePath
                  simulatorInfo:(SimulatorInfo *)simInfo
                      reporters:(NSArray *)reporters
                          error:(NSString **)error
{
  NSError *localError = nil;
  SimDevice *device = [simInfo simulatedDevice];
  NSURL *appURL = [NSURL fileURLWithPath:testHostBundlePath];

  if (![self prepareSimulatorWithSimulatorInfo:simInfo error:&localError]) {
    *error = [NSString stringWithFormat:
              @"Simulator '%@' was not prepared: %@",
              [simInfo simulatedDevice].name, localError.localizedDescription ?: @"Failed for unknown reason."];
    return NO;
  }

  BOOL installed = [device installApplication:appURL
                                  withOptions:@{@"CFBundleIdentifier": testHostBundleID}
                                        error:&localError];

  if (!installed) {
    *error = [NSString stringWithFormat:
              @"Failed to install the test host app '%@': %@",
              testHostBundleID, localError.localizedDescription ?: @"Failed for unknown reason."];

  }
  return installed;
}

@end

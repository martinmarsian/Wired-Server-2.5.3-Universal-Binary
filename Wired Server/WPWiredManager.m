/* $Id$ */

/*
 *  Copyright (c) 2009 Axel Andersson
 *  All rights reserved.
 *
 *  Redistribution and use in source and binary forms, with or without
 *  modification, are permitted provided that the following conditions
 *  are met:
 *  1. Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 *  2. Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR ``AS IS'' AND ANY EXPRESS OR
 * IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT,
 * STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
 * ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 */

#import <Security/Authorization.h>
#import "WPError.h"
#import "WPSettings.h"
#import "WPWiredManager.h"

#define WPLibraryPath					@"~/Library"
#define WPWiredDataPath					@"/Library/Wired/data"
#define WPWiredBinaryPath				@"/Library/Wired/wired"
#define WPWiredLaunchDaemonPlistPath		@"/Library/LaunchDaemons/fr.read-write.WiredServer.plist"

@interface WPWiredManager(Private)

- (NSString *)_versionForWiredAtPath:(NSString *)path;

- (BOOL)_reloadPidFile;
- (BOOL)_reloadStatusFile;

- (BOOL)_ensureAuthorizationWithErrorCode:(NSInteger)errorCode error:(WPError **)outError;
- (BOOL)_runPrivilegedPath:(NSString *)path arguments:(NSArray<NSString *> *)arguments errorCode:(NSInteger)errorCode error:(WPError **)outError;

@end


@implementation WPWiredManager(Private)

- (NSString *)_versionForWiredAtPath:(NSString *)path {
	NSTask			*task;
	NSString		*string;
	NSData			*data;

	if(![[NSFileManager defaultManager] isExecutableFileAtPath:path])
		return NULL;

	task = [[[NSTask alloc] init] autorelease];
	[task setLaunchPath:path];
	[task setArguments:[NSArray arrayWithObject:@"-v"]];
	[task setStandardOutput:[NSPipe pipe]];
	[task setStandardError:[task standardOutput]];
	[task launch];
	[task waitUntilExit];

	data = [[[task standardOutput] fileHandleForReading] readDataToEndOfFile];

	if(data && [data length] > 0) {
		string = [NSString stringWithData:data encoding:NSUTF8StringEncoding];

		if(string && [string length] > 0)
			return [string stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	}

	return NULL;
}



- (BOOL)_reloadPidFile {
	NSString		*string, *command;
	BOOL			running = NO;

	string = [NSString stringWithContentsOfFile:[self pathForFile:@"wired.pid"]
									   encoding:NSUTF8StringEncoding
										  error:NULL];

	if(string) {
		command = [[NSWorkspace sharedWorkspace] commandForProcessIdentifier:[string unsignedIntValue]];

		if([command isEqualToString:@"wired"]) {
			_pid = [string unsignedIntegerValue];

			running = YES;
		} else {
            [[NSFileManager defaultManager] removeItemAtPath:[self pathForFile:@"wired.pid"] error:nil];
		}
	}

	if(running != _running) {
		_running = running;

		return YES;
	}

	return NO;
}



- (BOOL)_reloadStatusFile {
	NSString		*string;
	NSArray			*status;
	NSDate			*date;

	string = [NSString stringWithContentsOfFile:[self pathForFile:@"wired.status"]
									   encoding:NSUTF8StringEncoding
										  error:NULL];

	if(string) {
		status = [string componentsSeparatedByString:@" "];
		date = [NSDate dateWithTimeIntervalSince1970:[[status objectAtIndex:0] intValue]];

		if(!_launchDate || ![date isEqualToDate:_launchDate]) {
			[_launchDate release];
			_launchDate = [date retain];

			return YES;
		}
	} else {
		if(_launchDate) {
			[_launchDate release];
			_launchDate = NULL;

			return YES;
		}
	}

	return NO;
}



- (BOOL)_ensureAuthorizationWithErrorCode:(NSInteger)errorCode error:(WPError **)outError {
	OSStatus status;

	// Create the authorization reference once; it lives for the lifetime of this object.
	if(!_authRef) {
		status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
									 kAuthorizationFlagDefaults, &_authRef);
		if(status != errAuthorizationSuccess) {
			if(outError)
				*outError = [WPError errorWithDomain:WPPreferencePaneErrorDomain
											   code:errorCode
										   argument:[NSString stringWithFormat:@"AuthorizationCreate failed (%d)", (int)status]];
			return NO;
		}
	}

	// Request execute rights.
	// • If the credential is still cached in the Security Server session (300 s),
	//   this succeeds silently and resets the timer — no dialog is shown.
	// • Otherwise the dialog appears. On macOS 14+ with Touch ID hardware, the
	//   system.privilege.admin right natively offers Touch ID in this dialog.
	// kAuthorizationFlagExtendRights resets the 300-second timeout on each
	// successful call, so any use within 5 minutes of the last one is prompt-free.
	AuthorizationItem right = { kAuthorizationRightExecute, 0, NULL, 0 };
	AuthorizationRights rights = { 1, &right };
	AuthorizationFlags flags = kAuthorizationFlagDefaults
							 | kAuthorizationFlagInteractionAllowed
							 | kAuthorizationFlagPreAuthorize
							 | kAuthorizationFlagExtendRights;

	status = AuthorizationCopyRights(_authRef, &rights, NULL, flags, NULL);
	if(status != errAuthorizationSuccess) {
		// Discard the ref on failure so the next call starts fresh.
		AuthorizationFree(_authRef, kAuthorizationFlagDestroyRights);
		_authRef = NULL;
		// errAuthorizationCanceled: user dismissed the dialog — no error to display
		if(outError && status != errAuthorizationCanceled)
			*outError = [WPError errorWithDomain:WPPreferencePaneErrorDomain
										   code:errorCode
									   argument:[NSString stringWithFormat:@"Authorization denied (%d)", (int)status]];
		return NO;
	}

	return YES;
}



- (BOOL)_runPrivilegedPath:(NSString *)path
				 arguments:(NSArray<NSString *> *)arguments
				 errorCode:(NSInteger)errorCode
					 error:(WPError **)outError {
	OSStatus status;

	if(![self _ensureAuthorizationWithErrorCode:errorCode error:outError])
		return NO;

	// Build a C-string argument array required by AuthorizationExecuteWithPrivileges
	char **args = malloc((arguments.count + 1) * sizeof(char *));
	for(NSUInteger i = 0; i < arguments.count; i++)
		args[i] = (char *)[arguments[i] UTF8String];
	args[arguments.count] = NULL;

	// Run the tool as root; reading the pipe until EOF waits for the process to finish
	FILE *pipe = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	status = AuthorizationExecuteWithPrivileges(_authRef,
												[path fileSystemRepresentation],
												kAuthorizationFlagDefaults,
												args,
												&pipe);
#pragma clang diagnostic pop
	free(args);

	NSMutableString *output = [NSMutableString string];
	if(pipe) {
		char buffer[512];
		while(fgets(buffer, sizeof(buffer), pipe))
			[output appendString:@(buffer)];
		fclose(pipe);
	}

	// NOTE: _authRef is intentionally NOT freed here.
	// Keeping it alive lets kAuthorizationFlagExtendRights reset the 300-second
	// credential timeout on each call, avoiding repeated password prompts within
	// a session. The ref is released in -dealloc.

	if(status != errAuthorizationSuccess) {
		if(outError)
			*outError = [WPError errorWithDomain:WPPreferencePaneErrorDomain
										   code:errorCode
									   argument:[output length] > 0
												? output
												: [NSString stringWithFormat:@"Execution failed (%d)", (int)status]];
		return NO;
	}

	// All scripts write "WIREDSERVER_SCRIPT_OK" on success.
	// AuthorizationExecuteWithPrivileges does not expose the process exit code,
	// so this marker is the only reliable way to detect silent script failures.
	if([output rangeOfString:@"WIREDSERVER_SCRIPT_OK"].location == NSNotFound) {
		if(outError)
			*outError = [WPError errorWithDomain:WPPreferencePaneErrorDomain
										   code:errorCode
									   argument:[output length] > 0
												? output
												: @"Script did not complete successfully."];
		return NO;
	}

	return YES;
}

@end



@implementation WPWiredManager

- (id)init {
	self = [super init];

	_rootPath = [WPWiredDataPath retain];

	_statusTimer = [[NSTimer scheduledTimerWithTimeInterval:1.0
													 target:self
												   selector:@selector(statusTimer:)
												   userInfo:NULL
													repeats:YES] retain];

	[_statusTimer fire];

	return self;
}



- (void)dealloc {
	[_rootPath release];

	if(_authRef)
		AuthorizationFree(_authRef, kAuthorizationFlagDestroyRights);

	[super dealloc];
}



#pragma mark -

- (void)statusTimer:(NSTimer *)timer {
	BOOL		notify = NO;

	if([self _reloadPidFile])
		notify = YES;

	if([self isRunning]) {
		if([self _reloadStatusFile])
			notify = YES;
	}

	if(notify)
		[[NSNotificationCenter defaultCenter] postNotificationName:WPWiredStatusDidChangeNotification object:self];
}



#pragma mark -

- (NSString *)rootPath {
	return _rootPath;
}



- (NSString *)pathForFile:(NSString *)file {
	return [_rootPath stringByAppendingPathComponent:file];
}



#pragma mark -

- (BOOL)isInstalled {
	return [[NSFileManager defaultManager] isExecutableFileAtPath:WPWiredBinaryPath];
}



- (BOOL)isRunning {
	return _running;
}


- (NSDate *)launchDate {
	return _launchDate;
}



- (NSString *)installedVersion {
	return [self _versionForWiredAtPath:WPWiredBinaryPath];
}



- (NSString *)packagedVersion {
	return [self _versionForWiredAtPath:[[[self bundle] resourcePath] stringByAppendingPathComponent:@"Wired/wired"]];
}



#pragma mark -

- (void)setLaunchesAutomatically:(BOOL)launchesAutomatically {
	NSString	*value;

	// Update the Disabled key in the LaunchDaemon plist using PlistBuddy (requires root)
	value = launchesAutomatically ? @"false" : @"true";

	[self _runPrivilegedPath:@"/usr/libexec/PlistBuddy"
				   arguments:@[
					   @"-c",
					   [NSString stringWithFormat:@"Set :Disabled %@", value],
					   WPWiredLaunchDaemonPlistPath
				   ]
				   errorCode:WPPreferencePaneStartFailed
					   error:NULL];
}



- (BOOL)launchesAutomatically {
	NSDictionary *dictionary;

	// The LaunchDaemon plist is world-readable; no elevated privileges needed
	dictionary = [NSDictionary dictionaryWithContentsOfFile:WPWiredLaunchDaemonPlistPath];
	return ![dictionary boolForKey:@"Disabled"];
}



#pragma mark -

- (void)makeServerReloadConfig {
	// wired runs as a dedicated service user (different from this app's user) —
	// kill() would fail with EPERM.  Send SIGHUP as root via AEWP.
	NSString *pidPath = [self pathForFile:@"wired.pid"];
	NSString *cmd = [NSString stringWithFormat:
		@"PID=$(cat '%@' 2>/dev/null); [ -n \"$PID\" ] && kill -HUP \"$PID\" 2>/dev/null; echo WIREDSERVER_SCRIPT_OK",
		[pidPath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
	[self _runPrivilegedPath:@"/bin/sh"
				   arguments:@[@"-c", cmd]
				   errorCode:WPPreferencePaneStartFailed
					   error:NULL];
}



- (void)_runRebuildIndex {
	// Prefer the deployed copy; fall back to the bundle for dev/manual installs.
	NSString *rebuildPath = @"/Library/Wired/rebuild-index.sh";
	if(![[NSFileManager defaultManager] fileExistsAtPath:rebuildPath])
		rebuildPath = [[self bundle] pathForResource:@"rebuild-index" ofType:@"sh" inDirectory:@"Wired"];
	if(!rebuildPath)
		return;

	// Run via "launchctl asuser <uid>" so the script executes in the logged-in
	// user's login session where TCC grants for removable/external volumes are
	// honoured.  Direct NSTask execution inherits the host app's (System
	// Settings') TCC grants, which do not include removable volumes — so find(1)
	// silently returns 0 results.  launchctl asuser requires root, so we go
	// through _runPrivilegedPath: (AuthorizationExecuteWithPrivileges).
	uid_t uid = getuid();
	NSString *quotedPath = [NSString stringWithFormat:@"'%@'",
		[rebuildPath stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"]];
	NSString *cmd = [NSString stringWithFormat:
		@"launchctl asuser %u /bin/sh %@ && echo WIREDSERVER_SCRIPT_OK",
		(unsigned int)uid, quotedPath];

	[self _runPrivilegedPath:@"/bin/sh"
				   arguments:@[@"-c", cmd]
				   errorCode:WPPreferencePaneStartFailed
					   error:nil];
}



- (void)makeServerIndexFiles {
	// wired runs as a dedicated service user (LaunchDaemon) which may not have
	// TCC access to external volumes.  Run rebuild-index.sh via
	// "launchctl asuser <uid>" so indexing uses the logged-in user's TCC
	// context where removable-volume grants are honoured.
	[self _runRebuildIndex];
}



#pragma mark -

- (BOOL)installWithError:(WPError **)error {
	BOOL result;

	// Use /bin/sh explicitly so execute permission on the script is not required.
	result = [self _runPrivilegedPath:@"/bin/sh"
							arguments:@[
								[[self bundle] pathForResource:@"install" ofType:@"sh"],
								[[self bundle] resourcePath],
								[WPLibraryPath stringByExpandingTildeInPath],
								[[WPSettings settings] boolForKey:WPMigratedWired13] ? @"NO" : @"YES"
							]
							errorCode:WPPreferencePaneInstallFailed
								error:error];

	if(result)
		[[WPSettings settings] setBool:YES forKey:WPMigratedWired13];

	return result;
}



- (BOOL)uninstallWithError:(WPError **)error {
	return [self _runPrivilegedPath:@"/bin/sh"
						  arguments:@[
							  [[self bundle] pathForResource:@"uninstall" ofType:@"sh"],
							  [WPLibraryPath stringByExpandingTildeInPath]
						  ]
						  errorCode:WPPreferencePaneUninstallFailed
							  error:error];
}


- (BOOL)updateWithError:(WPError **)error {
	return [self _runPrivilegedPath:@"/bin/sh"
						  arguments:@[
							  [[self bundle] pathForResource:@"update" ofType:@"sh"],
							  [[self bundle] resourcePath],
							  [WPLibraryPath stringByExpandingTildeInPath]
						  ]
						  errorCode:WPPreferencePaneInstallFailed
							  error:error];
}


- (BOOL)startWithError:(WPError **)error {
	BOOL result;
	NSString *scriptPath;

	// Stop any currently-running instance first so that it releases its
	// SQLite connection before start.sh re-bootstraps the LaunchDaemon.
	// stop.sh always emits WIREDSERVER_SCRIPT_OK, so this succeeds even when
	// wired is not currently running.
	[self stopWithError:nil];

	// start.sh:
	//   1. ensures the macOS service user/group from wired.conf exist
	//   2. fixes ownership and regenerates the LaunchDaemon plist
	//   3. bootstraps the daemon into the system domain via launchctl
	//   4. pre-builds the file index via rebuild-index.sh in the logged-in
	//      user's TCC session (launchctl asuser) so external-volume listings
	//      are available even without Full Disk Access granted to the daemon
	scriptPath = [[self bundle] pathForResource:@"start" ofType:@"sh"];
	result = [self _runPrivilegedPath:@"/bin/sh"
							arguments:@[scriptPath, [WPLibraryPath stringByExpandingTildeInPath]]
							errorCode:WPPreferencePaneStartFailed
								error:error];

	[_statusTimer fire];

	return result;
}



- (BOOL)restartWithError:(WPError **)error {
	if(![self stopWithError:error])
		return NO;

	if(![self startWithError:error])
		return NO;

	return YES;
}



- (BOOL)stopWithError:(WPError **)error {
	BOOL result;
	NSString *scriptPath;

	// stop.sh passes LIBRARY so it can also clean up a legacy LaunchAgent
	// entry in the gui/<uid> domain during migration.
	scriptPath = [[self bundle] pathForResource:@"stop" ofType:@"sh"];
	result = [self _runPrivilegedPath:@"/bin/sh"
							arguments:@[scriptPath, [WPLibraryPath stringByExpandingTildeInPath]]
							errorCode:WPPreferencePaneStopFailed
								error:error];

	[_statusTimer fire];

	return result;
}

@end

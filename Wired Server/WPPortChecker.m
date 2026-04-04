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

#import "WPPortChecker.h"

@implementation WPPortChecker

#pragma mark -

- (void)setDelegate:(id)newDelegate {
    delegate = newDelegate;
}

- (id)delegate {
    return delegate;
}

#pragma mark -

// Parse the nmap-style text returned by api.hackertarget.com/nmap/:
//   "4871/tcp  open   unknown"  → Open
//   "4871/tcp  closed unknown"  → Closed
//   "4871/tcp  filtered  ..."   → Filtered
// Any other response (error text, rate-limit message, …) → Failed.
- (WPPortCheckerStatus)_statusFromNmapOutput:(NSString *)output port:(NSUInteger)port {
    NSString *portPrefix = [NSString stringWithFormat:@"%lu/tcp", (unsigned long)port];

    for (NSString *line in [output componentsSeparatedByString:@"\n"]) {
        if ([line hasPrefix:portPrefix]) {
            if ([line rangeOfString:@" open "].location  != NSNotFound ||
                [line rangeOfString:@"\topen"].location != NSNotFound ||
                [line hasSuffix:@" open"])
                return WPPortCheckerOpen;

            if ([line rangeOfString:@" closed"].location != NSNotFound)
                return WPPortCheckerClosed;

            if ([line rangeOfString:@" filtered"].location != NSNotFound)
                return WPPortCheckerFiltered;
        }
    }
    return WPPortCheckerFailed;
}

// Two-step internet reachability check:
//   1. Resolve the machine's public IP via api.ipify.org
//   2. Ask api.hackertarget.com to run a one-port nmap scan against that IP
//
// This mirrors what the original wired.read-write.fr/port_check.php did
// (auto-detect caller's IP, probe the port from outside) without depending
// on the defunct server.
- (void)checkStatusForPort:(NSUInteger)port {
    _port = port;
    id<NSObject> retainedDelegate = (id<NSObject>)delegate;

    NSURL *ipURL = [NSURL URLWithString:@"https://api.ipify.org?format=plain"];

    [[[NSURLSession sharedSession]
        dataTaskWithURL:ipURL
        completionHandler:^(NSData *ipData, NSURLResponse *ipResp, NSError *ipErr) {

        void (^report)(WPPortCheckerStatus) = ^(WPPortCheckerStatus s) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if ([retainedDelegate respondsToSelector:
                        @selector(portChecker:didReceiveStatus:forPort:)])
                    [(id)retainedDelegate portChecker:self
                                    didReceiveStatus:s
                                             forPort:port];
            });
        };

        if (ipErr || !ipData) { report(WPPortCheckerFailed); return; }

        NSString *publicIP = [[[NSString alloc] initWithData:ipData
            encoding:NSUTF8StringEncoding] autorelease];
        publicIP = [publicIP stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];

        if (!publicIP.length) { report(WPPortCheckerFailed); return; }

        // Step 2 — nmap single-port scan from hackertarget
        NSString *urlStr = [NSString stringWithFormat:
            @"https://api.hackertarget.com/nmap/?q=%@:%lu",
            publicIP, (unsigned long)port];
        NSURL *nmapURL = [NSURL URLWithString:urlStr];

        [[[NSURLSession sharedSession]
            dataTaskWithURL:nmapURL
            completionHandler:^(NSData *nmapData, NSURLResponse *nmapResp, NSError *nmapErr) {

            if (nmapErr || !nmapData) { report(WPPortCheckerFailed); return; }

            NSString *output = [[[NSString alloc] initWithData:nmapData
                encoding:NSUTF8StringEncoding] autorelease];
            report([self _statusFromNmapOutput:output port:port]);

        }] resume];

    }] resume];
}

@end

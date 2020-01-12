/*
--- COPYRIGHT AND LICENSE ---

Copyright (c) 2018-2019, Takashi Shirakawa. All rights reserved.
e-mail: tkshirakawa@gmail.com
        shirakawa-takashi@kansaih.johas.go.jp

##########
In addition to the following BSD license, please let us know how the codes are used in your products, software, hardware, books, blogs, seminars and any other achievements or trials, prior to or at the time of the public release. We deeply appreciate your cooperation, understanding and contributions to our activities and efforts.
##########


Released under the BSD license.
URL: https://opensource.org/licenses/BSD-2-Clause

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/


#ifndef AIASPluginFilter_h
#define AIASPluginFilter_h




#import <OsiriXAPI/PluginFilter.h>


@interface AIASPluginFilter : PluginFilter

// Plugin entry point
- (long) filterImage:(NSString*)menuName;

+ (id) getWindowControllerForNib:(NSString*)nibName;

@end

#endif


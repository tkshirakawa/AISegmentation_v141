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


#ifndef AIASWindowController_h
#define AIASWindowController_h


#import <OsiriXAPI/ViewerController.h>
#import <OsiriXAPI/ROI.h>




#define IMG_SIZE        200
#define IMG_SQSIZE      40000




typedef struct {
    CGRect      rectInView, rectInRes200, rectInRes200CG;
    ROI*        selectedROI;
} CropRect_t;




@interface AIASWindowController : NSWindowController {

    CGColorSpaceRef CG_GRAY;
    CGRect          CG_RECT200;
    
    CGContextRef    CG_CONTX200;
    CGContextRef    CG_CONTX_ROI;

    
    IBOutlet NSButton *runAICore;
    IBOutlet NSPopUpButton *AICorePopup;
    IBOutlet NSTextField *AICoreDirPathText;
    
    IBOutlet NSComboBox *workDirPathBox;
    IBOutlet NSPopUpButton *imageExt;
    IBOutlet NSTextField *CTImageDirName;
    IBOutlet NSTextField *resultDirName;

    IBOutlet NSImageView *ResultImageView;
    IBOutlet NSImageView *AIOutputView;
    
    IBOutlet NSSlider *maskContrast;
    IBOutlet NSSlider *maskThreshold;
    IBOutlet NSButton *boolFillGaps;
    IBOutlet NSSlider *fillGaps;
//    IBOutlet NSSlider *maskErode;
    IBOutlet NSButton *keepSliceNum;
    IBOutlet NSButton *drawROI;
    IBOutlet NSColorWell *roiColor;
    IBOutlet NSTextField *roiSuffix;
    IBOutlet NSButton *createNewDCMSeries;
    IBOutlet NSButton *useGPU;
    IBOutlet NSTextField *SliceNumStrat;
    IBOutlet NSTextField *SliceNumLast;
    IBOutlet NSTextField *PixelSize;
    IBOutlet NSTextField *SliceIncrement;

    IBOutlet NSScrollView *MessageView;
}

- (id) loadAIASPlugin;
- (NSMutableDictionary*) getDefaults;
- (void) setupAICoresPopup:(NSString*)aiCoreDir;
- (void) setupWorkDirComboBox;

- (void) studyViewerWillClose:(NSNotification*)note;
- (void) AIASWindowWillClose:(NSNotification*)note;
- (void) viewerDidChange:(NSNotification*)note;

- (IBAction) userSelectAICoreDir:(id)sender;

- (IBAction) selectWorkFolder:(id)sender;

- (IBAction) computeByAI:(id)sender;
- (void) removeTemporaryCompiledModelc:(NSURL*)modelURL;
- (BOOL) performSegmentation:(const ViewerController*)viewer;
- (CropRect_t) makeCropRectData:(const ViewerController*)viewer pixelSize:(CGSize*)pixelSize;
- (NSBitmapImageRep*) makeCTImageForAIFrom:(const CGImageRef)img cropData:(const CropRect_t)cropData;
- (void) fillGapsIn:(NSBitmapImageRep*)inImg threshold:(const UInt8)thd strength:(const int)stg;
- (ROI*) makeROIFrom:(NSBitmapImageRep*)inImg cropData:(const CropRect_t)cropData aiROIName:(NSString*)aiROIName;
- (DICOMExport*) setUpDICOMExport:(const ViewerController*)viewer pixelSize:(const CGSize)pixS sliceThickness:(double)slth date:(const NSString*)dateStr roiName:(const NSString*)roiName;
- (void) addOutputToSeries:(NSBitmapImageRep*)inImg dcmExport:(DICOMExport*)e slicePositionX:(const float)x Y:(const float)y Z:(const float)z dcmPaths:(NSMutableArray*)dcmPaths;

- (IBAction)showInfoWindow:(id)sender;
- (void) appendMessage:(NSString*)mes;
- (void) appendError:(NSString*)mes error:(NSError*)errContent;
- (void) appendError:(NSString*)mes exception:(NSException*)exception;
- (void) appendError:(NSString*)mes;

@end

#endif



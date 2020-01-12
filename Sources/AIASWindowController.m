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


#import <OsiriXAPI/DicomStudy.h>
#import <OsiriXAPI/DicomSeries.h>
#import <OsiriXAPI/DicomImage.h>
#import <OsiriXAPI/DCMPix.h>
#import <OsiriXAPI/ROI.h>
#import <OsiriXAPI/Notifications.h>
#import <OsiriXAPI/DICOMExport.h>
#import "OsiriXAPI/browserController.h"
#import <OsiriXAPI/DicomDatabase.h>

#import <Accelerate/Accelerate.h>
#import <CoreGraphics/CoreGraphics.h>
#import <CoreML/CoreML.h>

#import "AIASCore.h"
#import "AIASWindowController.h"
#import "AIASPluginFilter.h"
#import "AIASInfoWindowController.h"




@implementation AIASWindowController


- (id) loadAIASPlugin
{
    //[NSUserDefaults.standardUserDefaults removePersistentDomainForName:[NSBundle mainBundle].bundleIdentifier];   // Dangerous!
    [NSUserDefaults.standardUserDefaults registerDefaults:[self getDefaults]];
    

    self = [super initWithWindowNibName:@"AIASWindow"];
    

	if (self)
	{
        // Show window
        [self showWindow:self];
        [self appendMessage:@"A.I.Segmentation plugin loaded."];

        [self setupAICoresPopup:[NSUserDefaults.standardUserDefaults stringForKey:@"SUD_AICoreDirPath"]];
        [self setupWorkDirComboBox];

        if (@available(macOS 10.14, *))
            [useGPU setEnabled:YES];
        else
        {
            [useGPU setState:NSControlStateValueOn];
            [useGPU setEnabled:NO];
        }


		const NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver: self
               selector: @selector(studyViewerWillClose:)
                   name: OsirixCloseViewerNotification
                 object: nil];
        [nc addObserver: self
               selector: @selector(AIASWindowWillClose:)
                   name: NSWindowWillCloseNotification
                 object: [self window]];
        [nc addObserver: self
               selector: @selector(viewerDidChange:)
                   name: OsirixViewerDidChangeNotification
                 object: nil];
        
        CG_GRAY = CGColorSpaceCreateWithName(kCGColorSpaceGenericGrayGamma2_2);
//        CG_GRAY = CGColorSpaceCreateWithName(kCGColorSpaceExtendedLinearGray);
        CG_RECT200 = CGRectMake(0, 0, IMG_SIZE, IMG_SIZE);
        CG_CONTX200 = CGBitmapContextCreate(nil, IMG_SIZE, IMG_SIZE, 8, 0, CG_GRAY, kCGImageAlphaNone);
        CG_CONTX_ROI = nil;
    }

	return self;
}




- (NSMutableDictionary*) getDefaults
{
    NSData* redColor = [NSKeyedArchiver archivedDataWithRootObject:[NSColor redColor]];

    NSMutableDictionary *defaults = [NSMutableDictionary dictionary];
    [defaults setObject:@"0"                    forKey:@"SUD_AICorePopupIndex"];
    [defaults setObject:@"CT images"            forKey:@"SUD_CTImageDirName"];
    [defaults setObject:@"AI results"           forKey:@"SUD_resultDirName"];
    [defaults setObject:@"0"                    forKey:@"SUD_imageExt"];
    [defaults setObject:@"0.0"                  forKey:@"SUD_maskContrast"];
    [defaults setObject:@"0.50"                 forKey:@"SUD_maskThreshold"];
    [defaults setObject:@"1"                    forKey:@"SUD_boolFillGaps"];
    [defaults setObject:@"1"                    forKey:@"SUD_fillGaps"];
    [defaults setObject:@"51"                   forKey:@"SUD_SliceNumStrat"];
    [defaults setObject:@"100"                  forKey:@"SUD_SliceNumLast"];
    [defaults setObject:@"1"                    forKey:@"SUD_keepSliceNum"];
    [defaults setObject:@"1"                    forKey:@"SUD_drawROI"];
    [defaults setObject:redColor                forKey:@"SUD_roiColor"];
    [defaults setObject:@"Suffix for ROI"       forKey:@"SUD_roiSuffix"];
    [defaults setObject:@"1"                    forKey:@"SUD_createNewDCMSeries"];
    [defaults setObject:@"1"                    forKey:@"SUD_useGPU"];
    return defaults;
}




- (void) setupAICoresPopup:(NSString*)aiCoreDir
{
    // Check
    const NSFileManager* defFM = NSFileManager.defaultManager;
    const NSArray* dirContents = aiCoreDir ? [[defFM contentsOfDirectoryAtPath:aiCoreDir error:nil] sortedArrayUsingSelector:@selector(compare:)] : nil;
    if (!dirContents)
    {
        [self appendMessage:@"Failed to find AI core folder."];
        return;
    }
    else if (dirContents.count == 0)
    {
        [self appendMessage:@"Empty AI core folder."];
        return;
    }

    if (![AICoreDirPathText.stringValue isEqualToString:aiCoreDir])
        [AICorePopup removeAllItems];
    [AICoreDirPathText setStringValue:aiCoreDir];
    [NSUserDefaults.standardUserDefaults setObject:aiCoreDir forKey:@"SUD_AICoreDirPath"];
    [NSUserDefaults.standardUserDefaults synchronize];

    // Add menus
    NSInteger nCores = 0;
    for (NSString* item in dirContents)
    {
        NSString* itemPath = [aiCoreDir stringByAppendingPathComponent:item];
        const NSDictionary* attDict = [defFM attributesOfItemAtPath:itemPath error:nil];

        if ([attDict.fileType isEqualToString:NSFileTypeDirectory])
        {
            if ([item.pathExtension isEqualToString:@"mlmodelc"])
            {
                //[AICorePopup insertItemWithTitle:item atIndex:0];
                [AICorePopup addItemWithTitle:item];
                nCores++;
            }
            else
            {
                const NSArray* c = [[defFM contentsOfDirectoryAtPath:itemPath error:nil] sortedArrayUsingSelector:@selector(compare:)];
                for (NSString* i in c)
                {
                    NSString* iPath = [itemPath stringByAppendingPathComponent:i];
                    if ([i.pathExtension isEqualToString:@"mlmodel"] || [i.pathExtension isEqualToString:@"mlmodelc"])
                    {
                        //[AICorePopup insertItemWithTitle:[iPath stringByReplacingOccurrencesOfString:aiCoreDir withString:@""] atIndex:0];
                        [AICorePopup addItemWithTitle:[iPath stringByReplacingOccurrencesOfString:aiCoreDir withString:@""]];
                        nCores++;
                    }
                }
            }
        }

        else if (![attDict.fileType isEqualToString:NSFileTypeSymbolicLink] && [item.pathExtension isEqualToString:@"mlmodel"])
        {
            //[AICorePopup insertItemWithTitle:item atIndex:0];
            [AICorePopup addItemWithTitle:item];
            nCores++;
        }
    }

    if (nCores) [AICorePopup selectItemAtIndex:MAX(MIN([NSUserDefaults.standardUserDefaults integerForKey:@"SUD_AICorePopupIndex"], nCores - 1), 0)];
    else        [self appendMessage:@"Valid A.I. cores were not found."];
}




- (void) setupWorkDirComboBox
{
    const NSArray *workDirPaths = [NSUserDefaults.standardUserDefaults arrayForKey:@"SUD_workDirPaths"];
    if (workDirPaths)
    {
        for (NSString* path in workDirPaths)
        {
            BOOL isDir;
            if ([NSFileManager.defaultManager fileExistsAtPath:path isDirectory:&isDir])
                if (isDir) [workDirPathBox addItemWithObjectValue:path];
        }

        if (workDirPathBox.numberOfItems > 0)
        {
            NSInteger index = [NSUserDefaults.standardUserDefaults integerForKey:@"SUD_workDirPathsIndex"];
            if (index >= workDirPathBox.numberOfItems)
            {
                index = workDirPathBox.numberOfItems - 1;
                [NSUserDefaults.standardUserDefaults setInteger:index forKey:@"SUD_workDirPathsIndex"];
            }
            [workDirPathBox selectItemAtIndex:index];
            [NSUserDefaults.standardUserDefaults setObject:workDirPathBox.objectValues forKey:@"SUD_workDirPaths"];
            [NSUserDefaults.standardUserDefaults synchronize];
        }
        else
            [workDirPathBox removeAllItems];
    }
    else
    {
        [workDirPathBox removeAllItems];
    }
}




// Will be called when "the study window" is closed
- (void) studyViewerWillClose:(NSNotification*)note
{
    [PixelSize setStringValue:@""];
    [SliceIncrement setStringValue:@""];
    [[[MessageView.documentView textStorage] mutableString] setString:@""];
}




// Will be called when "the plugin window" is closed
- (void) AIASWindowWillClose:(NSNotification*)note
{
    CGColorSpaceRelease(CG_GRAY);
    CGContextRelease(CG_CONTX200);
    CGContextRelease(CG_CONTX_ROI);

    [NSUserDefaults.standardUserDefaults setInteger:AICorePopup.indexOfSelectedItem forKey:@"SUD_AICorePopupIndex"];
    [NSUserDefaults.standardUserDefaults setInteger:workDirPathBox.indexOfSelectedItem forKey:@"SUD_workDirPathsIndex"];
    [NSUserDefaults.standardUserDefaults synchronize];
    
    [[self window] setAcceptsMouseMovedEvents:NO];
    [NSNotificationCenter.defaultCenter removeObserver:self];
    [self autorelease];
}




- (void) viewerDidChange:(NSNotification*)note
{
    [self studyViewerWillClose:note];
}




- (IBAction) userSelectAICoreDir:(id)sender
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setResolvesAliases:YES];
    [panel setCanCreateDirectories:NO];
    [panel setMessage:@"Select a folder containing A.I. cores you want to use."];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSInteger response)
    {
        if (response == NSModalResponseOK)
            [self setupAICoresPopup:[panel.URLs objectAtIndex:0].path];
    }];
}




- (IBAction) selectWorkFolder:(id)sender
{
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:NO];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    [panel setResolvesAliases:YES];
    [panel setCanCreateDirectories:YES];
    [panel setMessage:@"Select a -Work space- folder to save results in it."];
    [panel beginSheetModalForWindow:self.window completionHandler:^(NSInteger response)
    {
        if (response == NSModalResponseOK)
        {
            NSURL* selectedFolder = [panel.URLs objectAtIndex:0];
            const NSUInteger index = [workDirPathBox indexOfItemWithObjectValue:selectedFolder.path];
            if (index == NSNotFound)
            {
                [workDirPathBox insertItemWithObjectValue:selectedFolder.path atIndex:0];
                [workDirPathBox selectItemAtIndex:0];
                [NSUserDefaults.standardUserDefaults setObject:workDirPathBox.objectValues forKey:@"SUD_workDirPaths"];
                [NSUserDefaults.standardUserDefaults setInteger:0 forKey:@"SUD_workDirPathsIndex"];
                [NSUserDefaults.standardUserDefaults synchronize];
            }
            else
                [workDirPathBox selectItemAtIndex:index];
        }
    }];
}




- (IBAction) computeByAI:(id)sender
{
    [self appendMessage:@"\n>>> A.I. sequence start."];
    

#define RETURN(X) { [self appendMessage:X]; return; }

    
    // Check folder names
    if ([workDirPathBox.stringValue isEqualToString:@""] ||
        [CTImageDirName.stringValue isEqualToString:@""] ||
        [resultDirName.stringValue isEqualToString:@""])
    {
        [self appendError:@"Empty folder name."];
        RETURN(@"End of sequence. -lost folder name-")
    }


    // Set current viewer
    const ViewerController* viewer = [ViewerController frontMostDisplayed2DViewer];
    if (!viewer)
    {
        [self appendError:@"Failed to find the front-most viewer."];
        RETURN(@"End of sequence. -lost viewer-")
    }
    
    
    // Check ROI
    if (!viewer.selectedROI || viewer.selectedROI.type != tROI || NSIsEmptyRect(viewer.selectedROI.rect))
    {
        [self appendError:@"Please select/draw \"Rectangle\" to define computation bounds for A.I. core."];
        RETURN(@"End of sequence. -invalid ROI-")
    }
    
    
    // Check dimension
    if (viewer.imageView.curDCM.pixelSpacingX != viewer.imageView.curDCM.pixelSpacingY)
    {
        [self appendError:@"CT image needs the same pixel spacing for X and Y."];
        RETURN(@"End of sequence. -Invalid pixel dimension-")
    }
    
    
    NSFileManager* defm = NSFileManager.defaultManager;
    

    // Check work space
    BOOL isDir;
    if ([defm fileExistsAtPath:workDirPathBox.stringValue isDirectory:&isDir])
    {
        BOOL goAhead = YES;
        if (!isDir)
        {
            const NSAlert* alert = [[[NSAlert alloc] init] autorelease];
            [alert setMessageText:@"File with the same name already exists."];
            [alert setInformativeText:[NSString stringWithFormat:@"Unable to overwrite the existing FILE. Please use the other name or location for work space.\nWork space: %@", workDirPathBox.stringValue]];
            [alert runModal];
            goAhead = NO;
        }
        else
        {
            NSString* workPath = workDirPathBox.stringValue;
            const NSArray* shallowContents = [defm contentsOfDirectoryAtPath:workPath error:nil];
            for (NSString* sc in shallowContents)
            {
                if ([sc hasPrefix:@"."]) continue;

                const NSAlert* alert = [[[NSAlert alloc] init] autorelease];
                [alert setMessageText:@"Work space folder with contents exists."];
                [alert setInformativeText:[NSString stringWithFormat:@"NOTE: the contents in the work space folder will be DELETED if you select to overwrite.\nWork space: %@", workPath]];
                [alert addButtonWithTitle:@"Cancel A.I."];      // First button
                [alert addButtonWithTitle:@"Overwrite"];        // Second button
                if ([alert runModal] == NSAlertSecondButtonReturn)
                {
                    NSError* errContent = nil;
                    NSString* dc;
                    const NSDirectoryEnumerator* deepContents = [defm enumeratorAtPath:workPath];
                    while (dc = [deepContents nextObject])
                        if (![defm removeItemAtPath:[workPath stringByAppendingPathComponent:dc] error:&errContent])
                        {
                            [self appendError:[NSString stringWithFormat:@"Failed to delete %@.", dc] error:errContent];
                            goAhead = NO;
                        }
                }
                else
                    goAhead = NO;
                break;
            }
        }
        if (!goAhead) RETURN(@"End of sequence.")
    }
    else
    {
        [self appendError:[@"Failed to find the selected work space folder: " stringByAppendingString:workDirPathBox.stringValue]];
        RETURN(@"End of sequence. -lost work space folder-")
    }


    // Create input and output directories
    if (![defm createDirectoryAtPath:[workDirPathBox.stringValue stringByAppendingPathComponent:CTImageDirName.stringValue] withIntermediateDirectories:YES attributes:nil error:nil])
    {
        [self appendError:[@"Failed to create a folder: " stringByAppendingString:CTImageDirName.stringValue]];
        RETURN(@"End of sequence. -failed CT image dir-")
    }
    if (![defm createDirectoryAtPath:[workDirPathBox.stringValue stringByAppendingPathComponent:resultDirName.stringValue] withIntermediateDirectories:YES attributes:nil error:nil])
    {
        [self appendError:[@"Failed to create a folder: " stringByAppendingString:resultDirName.stringValue]];
        RETURN(@"End of sequence. -failed result dir-")
    }


    // run AI
    if ([self performSegmentation:viewer])  RETURN(@">>> End of sequence. -successful-")
    else                                    RETURN(@">>> End of sequence. -FAILURE-")


#undef RETURN
}




- (void) removeTemporaryCompiledModelc:(NSURL*)modelURL
{
    NSString* rt = modelURL.path.pathComponents[0];
    if ([rt isEqualToString:NSTemporaryDirectory()])
    {
        NSString* rm = modelURL.path.stringByDeletingLastPathComponent;
        [NSFileManager.defaultManager removeItemAtPath:rm error:nil];
        [self appendMessage:[NSString stringWithFormat:@"Compiled model for temporary use was removed: %@", rm]];
    }
}




- (BOOL) performSegmentation:(const ViewerController*)viewer
{
    // Get index range
    const int numberOfImages = viewer.currentSeries.numberOfImages.intValue;
    const int firstIndx = MAX(SliceNumStrat.intValue - 1, 0);
    const int lastIndx  = MAX(MIN(SliceNumLast.intValue, numberOfImages) - 1, firstIndx);
    const int slicesInRange = lastIndx - firstIndx + 1;
    NSError* errContent;
    BOOL errOccured = NO;


    // Display a waiting window and start timer
    NSDate* sequenceStart = [NSDate date];
    id waitWindow = [viewer startWaitProgressWindow:@"A.I.Segmentation > processing..." :(slicesInRange+2)];


    // Prepare data for AI
    BOOL compiledModel = NO;
    NSURL* modelURL = nil;
    NSString* corePath = nil;
    NSString* coreDir = [NSUserDefaults.standardUserDefaults stringForKey:@"SUD_AICoreDirPath"];
    errOccured = NO;
    if (AICorePopup.numberOfItems == 0 || !coreDir || coreDir.length <= 0)
    {
        [self appendError:@"Plese select your AI core folder. Temporary MLModel will be used."];
        errOccured = YES;
    }
    else
    {
        NSString* coreName = [NSString stringWithString:AICorePopup.titleOfSelectedItem];
        NSString* corePath = coreName.length > 0 ? [coreDir stringByAppendingPathComponent:coreName] : nil;
        BOOL isDir;
        if (!corePath || ![NSFileManager.defaultManager fileExistsAtPath:corePath isDirectory:&isDir])
        {
            [self appendError:@"Failed to find AI core folder. Temporary MLModel will be used."];
            errOccured = YES;
        }
        else if ([coreName.pathExtension isEqualToString:@"mlmodel"] && !isDir)
        {
            [self appendMessage:@"Compiling .mlmodel to .mlmodelc..."];
            modelURL = [MLModel compileModelAtURL:[NSURL fileURLWithPath:corePath] error:&errContent];
            compiledModel = YES;
            if (!modelURL)
            {
                [self appendError:@"Failed to compile selected .mlmodel file. Temporary MLModel will be used." error:errContent];
                errOccured = YES;
            }
        }
        else if ([coreName.pathExtension isEqualToString:@"mlmodelc"] && isDir)
        {
            [self appendMessage:@"Loading .mlmodelc file..."];
            modelURL = [NSURL fileURLWithPath:corePath];
        }
    }

    if (errOccured)     // Independent
    {
        modelURL = [[NSBundle bundleForClass:self.class] URLForResource:@"AIASCore" withExtension:@"mlmodel"];
        corePath = @"Temporary MLModel";
    }

    #define RETURN(X) { [viewer endWaitWindow:waitWindow]; return X; }

    if (!modelURL)      // Independent
    {
        [self appendError:@"Failed to prepare CoreML model."];
        RETURN(NO)
    }

    // MLMultiArray : C x H x W layout for images, where C is the number of channels, H is the height of the image, and W is the width.
    // Input grayscale image will be passed to a ML model in MLMultiArray with 1 x IMG_SIZE x IMG_SIZE (Channel x Height x Width).
    // Predicted image must be grayscale, saved in MLMultiArray with 1x200x200 (Channel x Height x Width).
    // AI, inputMArray, outputBMP should be released afterwards
    AIASCore* AI = nil;
    @try
    {
        if (@available(macOS 10.14, *))
        {
            MLModelConfiguration* conf = [[[MLModelConfiguration alloc] init] autorelease];
            [conf setComputeUnits:(useGPU.state == NSControlStateValueOn ? MLComputeUnitsAll : MLComputeUnitsCPUOnly)];
            AI = [[AIASCore alloc] initWithContentsOfURL:modelURL configuration:conf error:&errContent];
        }
        else
            AI = [[AIASCore alloc] initWithContentsOfURL:modelURL error:&errContent];
    }
    @catch (NSException* exception)
    {
        [self appendError:@"Exception: " exception:exception];
    }

    if (!AI)
    {
        [self appendError:@"Failed to allocate CoreML model." error:errContent];
        if (compiledModel) [self removeTemporaryCompiledModelc:modelURL];
        RETURN(NO)
    }

    MLMultiArray* inputMArray = [[MLMultiArray alloc] initWithShape:@[@1, @IMG_SIZE, @IMG_SIZE] dataType:MLMultiArrayDataTypeDouble error:&errContent];
    NSBitmapImageRep* outputBMP = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: nil
                                                                          pixelsWide: IMG_SIZE      pixelsHigh: IMG_SIZE
                                                                       bitsPerSample: 8        samplesPerPixel: 1
                                                                            hasAlpha: NO              isPlanar: NO
                                                                      colorSpaceName: NSCalibratedWhiteColorSpace
                                                                         bytesPerRow: IMG_SIZE    bitsPerPixel: 0 ];    // bytesPerRow must be IMG_SIZE
//    [self appendMessage:[NSString stringWithFormat:@"outputRowBytes %ld", outputBMP.bytesPerRow]];
    if (!inputMArray || !outputBMP)
    {
        [self appendError:@"Failed to prepare data structures." error:errContent];
        if (AI) [AI release];
        if (inputMArray) [inputMArray release];
        if (outputBMP) [outputBMP release];
        if (compiledModel) [self removeTemporaryCompiledModelc:modelURL];
        RETURN(NO)
    }

    
    // Make cropping rect data
    // pixelSizeMM is width and height of DICOM images in pixels when input, while square size of a single pixel of 200x200 result images in mm when output
    const long pwidth = viewer.imageView.curDCM.pwidth;
    const long pheight = viewer.imageView.curDCM.pheight;
    CGSize pixelSizeMM = {pwidth, pheight};
    CropRect_t cropData = [self makeCropRectData:viewer pixelSize:&pixelSizeMM];
    
    
    dispatch_queue_t GCDqueue_conc = dispatch_queue_create("jp.takashi.A.I.Segmentation.concurrentqueue", DISPATCH_QUEUE_CONCURRENT);
    dispatch_group_t GCDgroup_conc = dispatch_group_create();
    dispatch_queue_t GCDqueue_seri = dispatch_queue_create("jp.takashi.A.I.Segmentation.serialqueue", DISPATCH_QUEUE_SERIAL);
    dispatch_group_t GCDgroup_seri = dispatch_group_create();
    
    
    // Constract array of CGImageRef prior to the following main loop
    NSMutableArray<DCMPix*>* dcmPixList = [NSMutableArray arrayWithCapacity:slicesInRange];
    __block CGImageRef* cgImageList = malloc(slicesInRange * sizeof(CGImageRef));
    __block unsigned char* cgImageBaseAddr = malloc(slicesInRange * pwidth * pheight * sizeof(unsigned char));
    __block BOOL cgImageError = NO;
    dispatch_group_async(GCDgroup_conc, GCDqueue_conc, ^{
        register const size_t plen = pwidth * pheight;
        float *f_tmp1 = malloc(plen * sizeof(float)), *f_tmp2 = malloc(plen * sizeof(float));
        const float low = viewer.curWL - 0.5 * MAX(viewer.curWW, 1.0), upp = viewer.curWL + 0.5 * MAX(viewer.curWW, 1.0);
        const float mulp = 255.0 / (upp - low), bias = -low * mulp;
        const float black = 0.0, white = 255.0;
        
        for (register int i = firstIndx; i <= lastIndx; i++)
        {
            DCMPix* pix = [viewer.pixList objectAtIndex:(viewer.imageView.flippedData ? numberOfImages-i-1 : i)];
            [dcmPixList addObject:pix];
            unsigned char* dataPtr = cgImageBaseAddr + (i - firstIndx) * plen;
            vDSP_vsmsa(pix.fImage, 1, &mulp, &bias, f_tmp1, 1, plen);
            vDSP_vclip(f_tmp1, 1, &black, &white, f_tmp2, 1, plen);
            vDSP_vfixru8(f_tmp2, 1, dataPtr, 1, plen);
            CGDataProviderRef dp = CGDataProviderCreateWithData(NULL, dataPtr, plen, nil);
            CGImageRef img = dp ? CGImageCreate(pwidth, pheight, 8, 8, pwidth, CG_GRAY, (CGBitmapInfo)kCGImageAlphaNone, dp, NULL, true, kCGRenderingIntentDefault) : nil;
            CGDataProviderRelease(dp);      // CGDataProviderRef must be released.
            if (img)
            {
                cgImageList[i-firstIndx] = CGImageCreateWithImageInRect(img, cropData.rectInView);
                CGImageRelease(img);            // CGImageRef must be released.
            }
            else
            {
                cgImageError = YES;
                break;
            }
        }
        
        free(f_tmp1);
        free(f_tmp2);
    });

    
    const NSString* imgExt = imageExt.titleOfSelectedItem;
    const NSString* CTImageDirPath = [workDirPathBox.stringValue stringByAppendingPathComponent:CTImageDirName.stringValue];
    const NSString* resultDirPath = [workDirPathBox.stringValue stringByAppendingPathComponent:resultDirName.stringValue];
    NSDateFormatter* formatter = [[[NSDateFormatter alloc] init] autorelease];      [formatter setDateFormat:@"YYYY.MM.dd-HH.mm.ss"];
    NSString* sequenceStartStr = [formatter stringFromDate:sequenceStart];


    // Setup for drawing ROI
    NSString* aiROIName = nil;
    NSString* aiROIComment = nil;
    if (drawROI.state == NSControlStateValueOn)
    {
        aiROIName = [NSString stringWithFormat:@"AIS_ROI_%@", roiSuffix.stringValue];
        aiROIComment = [NSString stringWithFormat:@"Created by A.I.Segmentation\nComputation rectangle: %@\nA.I. core: %@", cropData.selectedROI.name, corePath];
        [viewer deleteSeriesROIwithName:aiROIName];     // Delete ROI(s) with the same name
        if (!CG_CONTX_ROI)
            CG_CONTX_ROI = CGBitmapContextCreate(nil, cropData.rectInView.size.width, cropData.rectInView.size.height, 8, 0, CG_GRAY, kCGImageAlphaNone);
    }


    // Setup DICOM exporter for new series
    DICOMExport* dcmExport = nil;
    NSBitmapImageRep* blackBmp = nil;
    NSMutableArray* dcmPaths = nil;
    const double sliceInterval = viewer.imageView.curDCM.sliceInterval;
    const double sliceThickness = viewer.imageView.curDCM.sliceThickness;
    if (createNewDCMSeries.state == NSControlStateValueOn)
    {
        dcmExport = [self setUpDICOMExport:viewer pixelSize:pixelSizeMM sliceThickness:sliceThickness date:sequenceStartStr roiName:aiROIName];
        if (dcmExport)
        {
            dcmPaths = [NSMutableArray array];
            CGContextSetGrayFillColor(CG_CONTX200, 0.0, 1.0);
            CGContextFillRect(CG_CONTX200, CG_RECT200);
            CGImageRef cgImg = CGBitmapContextCreateImage(CG_CONTX200);
            blackBmp = [[[NSBitmapImageRep alloc] initWithCGImage:cgImg] autorelease];      CGImageRelease(cgImg);
            double z = dcmPixList[0].originZ + (viewer.imageView.flippedData ? +sliceInterval : -sliceInterval);
            [self addOutputToSeries:blackBmp dcmExport:dcmExport slicePositionX:dcmPixList[0].originX Y:dcmPixList[0].originY Z:z dcmPaths:dcmPaths];
        }
        else
            [self appendError:@"Failed to prepare new DICOM series for prediction results."];
    }


    [viewer waitIncrementBy:waitWindow :1];
    dispatch_group_wait(GCDgroup_conc, DISPATCH_TIME_FOREVER);
    if (cgImageError)
    {
        if (compiledModel) [self removeTemporaryCompiledModelc:modelURL];
        RETURN(NO)
    }


    for (register int i = firstIndx; i <= lastIndx; i++)
    {
        [self appendMessage:[NSString stringWithFormat:@"Segmentation : slice %04d", i+1]];
        register int i0 = i - firstIndx;
//        register int curImage = viewer.imageView.flippedData ? numberOfImages-i-1 : i;
//        [self appendMessage:[NSString stringWithFormat:@"curImage1 %d, curImage2 %d", viewer.imageView.curImage, curImage]];

        // Crop image from selected ROI in the present OsiriX window
        // You should treat the resulting bitmap NSBitmapImageRep object as read only.
        NSBitmapImageRep* inputBMP = [self makeCTImageForAIFrom:cgImageList[i0] cropData:cropData];
        CGImageRelease(cgImageList[i0]);

        if (inputBMP)
        {
            // Convert image to data
            {
                double tmp[IMG_SQSIZE];
                const double c = 1.0 / 255.0;
                vDSP_vfltu8D(inputBMP.bitmapData, 1, tmp, 1, IMG_SQSIZE);            // Convert unsigned char to double
                vDSP_vsmulD(tmp, 1, &c, inputMArray.dataPointer, 1, IMG_SQSIZE);     // Multiply 1/255
            }
            

            // Prediction by CoreML model
            AIASCoreOutput* pred = nil;
            @try
            {
                pred = [AI predictionFromInput:inputMArray error:&errContent];
                if (!pred || !pred.output)
                {
                    [self appendError:@"Prediction error occured." error:errContent];
                    errOccured = YES;
                }
                else
                    errOccured = NO;
            }
            @catch (NSException* exception)
            {
                [self appendError:@"Prediction exception was thrown." exception:exception];
                errOccured = YES;
            }
            

            // Post processing
            if (errOccured)     // Break out this main loop
                break;

            else if (pred.output.shape[0].intValue != 1 ||          // Size of output image is invalid
                     pred.output.shape[1].intValue != IMG_SIZE ||
                     pred.output.shape[2].intValue != IMG_SIZE )
            {
                [self appendError:@"Prediction was performed but dimension of output array was not 1x200x200."];
                break;
            }

            else
            {
                // Convert data to image
                const double cnt = maskContrast.doubleValue;
                const double thd = maskThreshold.doubleValue;
                if (cnt < 0.001 && cnt > -0.001)        // Make output image black and white
                {
                    double tmp[IMG_SQSIZE], bitmapDataD255[IMG_SQSIZE];
                    const double c = 127.5;
                    vDSP_vthrscD(pred.output.dataPointer, 1, &thd, &c, tmp, 1, IMG_SQSIZE);
                    vDSP_vsaddD(tmp, 1, &c, bitmapDataD255, 1, IMG_SQSIZE);
                    vDSP_vfixru8D(bitmapDataD255, 1, outputBMP.bitmapData, 1, IMG_SQSIZE);
                    
                    // Fill small gaps in outputBMP image
                    if (boolFillGaps.state == NSControlStateValueOn)
                        [self fillGapsIn:outputBMP threshold:0 strength:fillGaps.intValue];
                }
                else        // Make output image gray-scale
                {
                    double tmp[IMG_SQSIZE], bitmapDataD255[IMG_SQSIZE];
                    const double c1 = 255.0 * cnt, c2 = 127.5 / c1 - c1 * thd;
                    const double black = 0.0, white = 255.0;
                    vDSP_vsmsaD(pred.output.dataPointer, 1, &c1, &c2, tmp, 1, IMG_SQSIZE);
                    vDSP_vclipD(tmp, 1, &black, &white, bitmapDataD255, 1, IMG_SQSIZE);
                    vDSP_vfixru8D(bitmapDataD255, 1, outputBMP.bitmapData, 1, IMG_SQSIZE);       // Convert double to unsigned char
                    
                    // Fill small gaps in outputBMP image
                    if (boolFillGaps.state == NSControlStateValueOn)
                        [self fillGapsIn:outputBMP threshold:round(thd*255.0) strength:fillGaps.intValue];
                }

                
                // Path for result
                NSString* fileName = [NSString stringWithFormat:@"%04d%@", (keepSliceNum.state==NSControlStateValueOn ? i+1 : i0+1), imgExt];

                
                // Save cropped/predicted image
                dispatch_group_async(GCDgroup_conc, GCDqueue_conc, ^{
                    const NSData* d = [imgExt isEqualToString:@".png"] ?
                        [inputBMP representationUsingType:NSBitmapImageFileTypePNG properties:[NSDictionary dictionaryWithObject:@NO forKey:NSImageInterlaced]] :
                        [inputBMP representationUsingType:NSBitmapImageFileTypeJPEG properties:[NSDictionary dictionaryWithObject:@1.0 forKey:NSImageCompressionFactor]];
                    if (d) [d writeToFile:[CTImageDirPath stringByAppendingPathComponent:fileName] atomically:YES];
                });
                dispatch_group_async(GCDgroup_conc, GCDqueue_conc, ^{
                    const NSData* d = [imgExt isEqualToString:@".png"] ?
                        [outputBMP representationUsingType:NSBitmapImageFileTypePNG properties:[NSDictionary dictionaryWithObject:@NO forKey:NSImageInterlaced]] :
                        [outputBMP representationUsingType:NSBitmapImageFileTypeJPEG properties:[NSDictionary dictionaryWithObject:@1.0 forKey:NSImageCompressionFactor]];
                    if (d) [d writeToFile:[resultDirPath stringByAppendingPathComponent:fileName] atomically:YES];
                });

                
                // Show cropped/predicted image
                [ResultImageView setImage:[[[NSImage alloc] initWithCGImage:inputBMP.CGImage size:NSZeroSize] autorelease]];
                [AIOutputView setImage:[[[NSImage alloc] initWithCGImage:outputBMP.CGImage size:NSZeroSize] autorelease]];


                // Draw predicted image in OsiriX window as an ROI
                if (drawROI.state == NSControlStateValueOn)
                {
                    ROI* roi = [self makeROIFrom:outputBMP cropData:cropData aiROIName:aiROIName];
                    if (roi)
                    {
                        [roi setCurView:viewer.imageView];
                        [roi setPix:dcmPixList[i0]];
                        [roi setSliceThickness:sliceThickness];
                        [roi setNSColor:roiColor.color globally:NO];
                        [roi setOpacity:0.4 globally:NO];
                        [roi setDisplayTextualData:YES];
                        [roi setComments:aiROIComment];
                        [[viewer.roiList objectAtIndex:(viewer.imageView.flippedData ? numberOfImages-i-1 : i)] addObject:roi];
                        [viewer.imageView update];
                    }
                    else
                        [self appendError:@"Failed to create ROI in OsiriX window."];
                }

                // Add predicted image to new DICOM series
                if (createNewDCMSeries.state == NSControlStateValueOn && dcmExport)
                {
                    dispatch_group_async(GCDgroup_seri, GCDqueue_seri, ^{
                        [self addOutputToSeries:outputBMP dcmExport:dcmExport slicePositionX:dcmPixList[i0].originX Y:dcmPixList[i0].originY Z:dcmPixList[i0].originZ dcmPaths:dcmPaths];
                    });
//                    [self appendMessage:[NSString stringWithFormat:@"pos %f,%f,%f", dcmPixList[i0].originX, dcmPixList[i0].originY, dcmPixList[i0].originZ]];
                }
            }
        }
        else
            [self appendError:@"Failed to create inputBMP from dicom view."];

        [viewer setImageIndex:i];
        [viewer waitIncrementBy:waitWindow :1];
//        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.001]];
    }


    if (AI) [AI release];
    if (inputMArray) [inputMArray release];
    if (outputBMP) [outputBMP release];
    if (cgImageList) free(cgImageList);
    if (cgImageBaseAddr) free(cgImageBaseAddr);
    if (compiledModel) [self removeTemporaryCompiledModelc:modelURL];


    // Set dimensional values for size conversion
    [PixelSize setFloatValue:pixelSizeMM.width];
    [SliceIncrement setFloatValue:sliceInterval];


    // End
    [viewer setImageIndex:firstIndx];
    const NSTimeInterval executionTime = [[NSDate date] timeIntervalSinceDate:sequenceStart];
    [self appendMessage:[NSString stringWithFormat:@"Prediction was performed in %.1f [sec].\nSee \"About this segmentation.txt\" in your work space for detals.", executionTime]];


    // Save parameter file
    [self appendMessage:[NSString stringWithFormat:@"Results by A.I. were saved in \"%@\".", resultDirPath]];
    dispatch_group_async(GCDgroup_conc, GCDqueue_conc, ^{
        NSString* parameterText = [NSString stringWithFormat:
                                   @"<About this examination>\nOsiriX window title\t\t%@\nPatient ID\t\t\t%@\nPatient name\t\t\t%@\nStudy name\t\t\t%@\nSeries description\t\t%@\nStudy instance UID\t\t%@\nSeries instance UID\t\t%@\nSeries number\t\t\t%@\nProtocol name\t\t\t%@\n\n<Computation parameters>\nComputation date\t\t%@\nDuration time\t\t\t%f [sec]\nA.I. core path\t\t\t%@\nWindow level/width\t\t%@ / %@\nIndex of slices\t\t\t%d - %d\nResult ROI name\t\t%@\nLeft upper corner of rect.ROI\tX: %f, Y: %f [pixel]\nRight lower corner of rect.ROI\tX: %f, Y: %f [pixel]\n\n<Dimensions of result images>\nPixel size for conversion\t%f [mm/pixel]\nSlice increment\t\t\t%f [mm]\n",
                                   viewer.window.title,
                                   viewer.currentStudy.patientID,
                                   viewer.currentStudy.name,
                                   viewer.currentStudy.studyName,
                                   viewer.currentSeries.name,
                                   viewer.currentStudy.studyInstanceUID,
                                   viewer.currentSeries.seriesInstanceUID,
                                   viewer.currentSeries.id,
                                   viewer.currentSeries.seriesDescription,
                                   sequenceStartStr, executionTime, corePath,
                                   viewer.currentSeries.windowLevel, viewer.currentSeries.windowWidth,
                                   firstIndx + 1, lastIndx + 1, aiROIName,
                                   cropData.selectedROI.rect.origin.x, cropData.selectedROI.rect.origin.y,
                                   cropData.selectedROI.rect.origin.x + cropData.selectedROI.rect.size.width,
                                   cropData.selectedROI.rect.origin.y + cropData.selectedROI.rect.size.height,
                                   pixelSizeMM.width, sliceInterval ];
        [parameterText writeToFile:[workDirPathBox.stringValue stringByAppendingPathComponent:@"About this segmentation.txt"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    });


    // Create new series from output
    if (createNewDCMSeries.state == NSControlStateValueOn && dcmExport)
    {
        [self appendMessage:@"Creating new DICOM series..."];
        dispatch_group_async(GCDgroup_seri, GCDqueue_seri, ^{
            double z = dcmPixList[slicesInRange-1].originZ + (viewer.imageView.flippedData ? -sliceInterval : +sliceInterval);
            [self addOutputToSeries:blackBmp dcmExport:dcmExport slicePositionX:dcmPixList[slicesInRange-1].originX Y:dcmPixList[slicesInRange-1].originY Z:z dcmPaths:dcmPaths];
            [BrowserController.currentBrowser.database addFilesAtPaths:[dcmPaths copy] postNotifications:YES dicomOnly:YES rereadExistingItems:YES generatedByOsiriX:YES];

            for (DicomSeries* series in viewer.currentStudy.allSeries)
            {
                if ([series.name containsString:sequenceStartStr])
                {
                    series.comment = [NSString stringWithFormat:@"Created by A.I.Segmentation. Date: %@, Source: %@, Slice: %d - %d, ROI name: %@",
                                      sequenceStartStr, viewer.currentSeries.name, firstIndx+1, lastIndx+1, aiROIName];
                    series.comment2 = [NSString stringWithFormat:@"A.I. core: %@, Work space: %@, Rect: (%f, %f) - (%f, %f)",
                                       corePath, workDirPathBox.stringValue, cropData.selectedROI.rect.origin.x, cropData.selectedROI.rect.origin.y,
                                       cropData.selectedROI.rect.origin.x + cropData.selectedROI.rect.size.width, cropData.selectedROI.rect.origin.y + cropData.selectedROI.rect.size.height];
                    break;
                }
            }
            [NSNotificationCenter.defaultCenter postNotificationName:OsirixAddToDBNotification object:self];
        });
    }


    dispatch_group_wait(GCDgroup_seri, DISPATCH_TIME_FOREVER);
    dispatch_group_wait(GCDgroup_conc, DISPATCH_TIME_FOREVER);
    dispatch_release(GCDqueue_seri);
    dispatch_release(GCDgroup_seri);
    dispatch_release(GCDqueue_conc);
    dispatch_release(GCDgroup_conc);


    RETURN(YES)
    #undef RETURN
}




- (CropRect_t) makeCropRectData:(const ViewerController*)viewer pixelSize:(CGSize*)pixelSizeMM
{
    CropRect_t cd;
    cd.selectedROI = viewer.selectedROI;

    // Calculate cropped image rect to be used (originally in viewer+CoreGraphics coordinate)
    int x = (int)floorf(cd.selectedROI.rect.origin.x);
    int y = (int)floorf(cd.selectedROI.rect.origin.y);
    int w = (int)ceilf(cd.selectedROI.rect.size.width);     w += (int)fmodf(w, 2);
    int h = (int)ceilf(cd.selectedROI.rect.size.height);    h += (int)fmodf(h, 2);
    int h_img = (int)roundf((*pixelSizeMM).height);
    cd.rectInView = CGRectIntersection(CGRectMake(x, y, w, h), CGRectMake(0, 0, roundf((*pixelSizeMM).width), h_img));
    CGRect rectInViewCG = cd.rectInView;
    rectInViewCG.origin.y = h_img - (rectInViewCG.origin.y + rectInViewCG.size.height);

    // Calculate offset from viewer coordinate to cropped+padded square (result square) coordinate
    CGPoint offset, offsetCG;
    double sf;
    if (h >= w)
    {
        offset.x = offsetCG.x = x - (h - w) / 2;
        offset.y = y;
        offsetCG.y = h_img - (y + h);
        sf = 200.0 / h;
    }
    else  // w > h
    {
        offset.x = offsetCG.x = x;
        offset.y = y - (w - h) / 2;
        offsetCG.y = h_img - (y + (w + h) / 2);
        sf = 200.0 / w;
    }
//    [self appendMessage:[NSString stringWithFormat:@"Ofst x %f, y %f", offset.x, offset.y]];
//    [self appendMessage:[NSString stringWithFormat:@"OfCG x %f, y %f", offsetCG.x, offsetCG.y]];
    
    // Offset cropped image rect into result square coordinate with the size of 200x200
    cd.rectInRes200 = CGRectMake(sf * (cd.rectInView.origin.x - offset.x),  sf * (cd.rectInView.origin.y - offset.y),
                                 sf * cd.rectInView.size.width,             sf * cd.rectInView.size.height);
    cd.rectInRes200CG = CGRectMake(sf * (rectInViewCG.origin.x - offsetCG.x),   sf * (rectInViewCG.origin.y - offsetCG.y),
                                   sf * rectInViewCG.size.width,                sf * rectInViewCG.size.height);

    if (cd.selectedROI.pixelSpacingX == cd.selectedROI.pixelSpacingY)   *pixelSizeMM = CGSizeMake(cd.selectedROI.pixelSpacingX/sf, cd.selectedROI.pixelSpacingX/sf);
    else                                                                *pixelSizeMM = CGSizeZero;
    return cd;
}




- (NSBitmapImageRep*) makeCTImageForAIFrom:(const CGImageRef)inImg cropData:(const CropRect_t)cropData
{
    CGContextSetGrayFillColor(CG_CONTX200, 0.0, 1.0);
    CGContextFillRect(CG_CONTX200, CG_RECT200);
    CGContextDrawImage(CG_CONTX200, cropData.rectInRes200CG, inImg);

    // Convert...
    // bytesPerRow = IMG_SIZE
    // If you use initWithCGImage, you should treat the resulting bitmap NSBitmapImageRep object as read only.
    CGImageRef cgImg = CGBitmapContextCreateImage(CG_CONTX200);
    NSBitmapImageRep* resultBMImg = [[[NSBitmapImageRep alloc] initWithCGImage:cgImg] autorelease];
    CGImageRelease(cgImg);

    return resultBMImg;
}




- (void) fillGapsIn:(NSBitmapImageRep*)inImg threshold:(const UInt8)thd strength:(const int)stg
{
#define COUNT_TH 5
    
    UInt8* bitmapData = inImg.bitmapData;
    if (!bitmapData) return;


    if (thd == 0)       // Output images are black and white
    {
        #define P(X,Y)  bitmapData[(Y)*IMG_SIZE+(X)]
        for (register int i = 1; i <= stg; i++)
        {
            for (register int ih = 1; ih < IMG_SIZE-1; ih++)
            for (register int iw = 1; iw < IMG_SIZE-1; iw++)
            {
                if (P(iw,ih) == 0 && P(iw-1,ih-1)+P(iw-1,ih)+P(iw-1,ih+1)+P(iw,ih+1)+P(iw+1,ih+1)+P(iw+1,ih)+P(iw+1,ih-1)+P(iw,ih-1) >= COUNT_TH*255)
                {
                    NSUInteger p255 = 255;
                    [inImg setPixel:&p255 atX:iw y:ih];
                }
            }
        }
        #undef P
    }
    else
    {
        UInt8 p[IMG_SIZE][IMG_SIZE];
        memcpy(*p, bitmapData, IMG_SQSIZE*sizeof(UInt8));
        for (register int i = 1; i <= stg; i++)
        {
            for (register int ih = 1; ih < 199; ih++)
            for (register int iw = 1; iw < 199; iw++)
            {
                if (p[iw][ih] < thd)
                {
                    register int count = 0, psum = 0;
                    if (p[iw-1][ih-1] >= thd) { count++; psum += p[iw-1][ih-1]; }
                    if (p[iw-1][ih  ] >= thd) { count++; psum += p[iw-1][ih  ]; }
                    if (p[iw-1][ih+1] >= thd) { count++; psum += p[iw-1][ih+1]; }
                    if (p[iw  ][ih+1] >= thd) { count++; psum += p[iw  ][ih+1]; }
                    if (p[iw+1][ih+1] >= thd) { count++; psum += p[iw+1][ih+1]; }
                    if (p[iw+1][ih  ] >= thd) { count++; psum += p[iw+1][ih  ]; }
                    if (p[iw+1][ih-1] >= thd) { count++; psum += p[iw+1][ih-1]; }
                    if (p[iw  ][ih-1] >= thd) { count++; psum += p[iw  ][ih-1]; }
                    if (count >= COUNT_TH)
                    {
                        NSUInteger newp = roundf((float)psum / (float)count);
                        [inImg setPixel:&newp atX:iw y:ih];
                    }
                }
            }
        }
    }

#undef COUNT_TH
}




- (ROI*) makeROIFrom:(NSBitmapImageRep*)inImg cropData:(const CropRect_t)cropData aiROIName:(NSString*)aiROIName
{
    const int wd = cropData.rectInView.size.width;
    const int ht = cropData.rectInView.size.height;

    CGImageRef cgImg = CGImageCreateWithImageInRect(inImg.CGImage, cropData.rectInRes200);
    CGContextDrawImage(CG_CONTX_ROI, CGRectMake(0, 0, wd, ht), cgImg);
    CGImageRelease(cgImg);

    // Set texture data
    unsigned char* texture = calloc(wd * ht, sizeof(unsigned char));    // Filled by zero
    const unsigned char* bitmapData = CGBitmapContextGetData(CG_CONTX_ROI);
    register const int bpr = (int)CGBitmapContextGetBytesPerRow(CG_CONTX_ROI);
    register int ihb, ihw;
    for (register int ih = 0; ih < ht; ih++)
    {
        ihb = ih * bpr;
        ihw = ih * wd;
        for (register int iw = 0; iw < wd; iw++)
            if (bitmapData[iw + ihb] > 127) texture[iw + ihw] = 0xFF;
    }

    // Create ROI
    return [[[ROI alloc] initWithTexture:texture    textWidth:wd    textHeight:ht    textName:aiROIName
                               positionX:cropData.rectInView.origin.x           positionY:cropData.rectInView.origin.y
                                spacingX:cropData.selectedROI.pixelSpacingX     spacingY:cropData.selectedROI.pixelSpacingY
                             imageOrigin:cropData.selectedROI.imageOrigin ] autorelease];
}




- (DICOMExport*) setUpDICOMExport:(const ViewerController*)viewer pixelSize:(const CGSize)pixS sliceThickness:(double)slth date:(const NSString*)dateStr roiName:(const NSString*)roiName
{
    DICOMExport* e = [[[DICOMExport alloc] init] autorelease];
    if (!e) return nil;


    DicomStudy* sourceStudy = viewer.currentStudy;
    DicomSeries* sourceSeries = viewer.currentSeries;
    float orientation[9];
    [viewer.imageView.curDCM orientation:orientation];


    [e setOffset:0];
    [e setSigned:NO];
    [e setModalityAsSource:YES];
    [e setSeriesDescription:[NSString stringWithFormat:@"AIS %@ %@ %@", dateStr, sourceSeries.name, (roiName ? roiName : @"-")]];
    [e setSeriesNumber:sourceSeries.id.longValue];
    [e setDefaultWWWL:sourceSeries.windowWidth.longValue :sourceSeries.windowLevel.longValue];
    [e setSlope:1];
    [e setPixelSpacing:pixS.width :pixS.height];
    [e setSliceThickness:slth];
    [e setOrientation:orientation];


    NSMutableDictionary* metaData = e.metaDataDict;

    [metaData setValue: sourceStudy.name forKey: @"patientsName"];
    [metaData setValue: sourceStudy.name forKey: @"patientName"];
    
    [metaData setValue: [sourceStudy valueForKey: @"patientID"] forKey: @"patientID"];
    
    [metaData setValue: [sourceStudy valueForKey: @"dateOfBirth"] forKey: @"patientsBirthdate"];
    [metaData setValue: [sourceStudy valueForKey: @"dateOfBirth"] forKey: @"patientBirthdate"];
    
    [metaData setValue: [sourceStudy valueForKey: @"patientSex"] forKey: @"patientsSex"];
    [metaData setValue: [sourceStudy valueForKey: @"patientSex"] forKey: @"patientSex"];
    
    [metaData setValue: [sourceStudy valueForKey: @"date"] forKey: @"studyDate"];
    
    [metaData setValue: [sourceStudy valueForKey: @"studyName"] forKey: @"studyDescription"];
    
    [metaData setValue: [sourceStudy valueForKey: @"modality"] forKey: @"modality"];

    [metaData setValue: [sourceStudy valueForKey: @"studyInstanceUID"] forKey: @"studyUID"];
    [metaData setValue: [sourceStudy valueForKey: @"studyID"] forKey: @"studyID"];


    return e;
}




- (void) addOutputToSeries:(NSBitmapImageRep*)inImg dcmExport:(DICOMExport*)e slicePositionX:(const float)x Y:(const float)y Z:(const float)z dcmPaths:(NSMutableArray*)dcmPaths
{
    float position[3] = {x, y, z};
    [e setPosition:position];
    [e setSlicePosition:z];
    [e setBitmapImageRep:inImg];

    NSString* file = [e writeDCMFile:nil];
    if (file) [dcmPaths addObject:file];
}




//- (void) doPostProcess
//{
//    NSBundle* bundle = [NSBundle bundleForClass:self.class];
//    NSString* path = [bundle pathForResource:@"xxx" ofType:@"pdf"];
//    if (!path)
//    {
//        [self appendError:@"Failed to find the file."];
//        return;
//    }
//
//    if ([[NSWorkspace sharedWorkspace] openFile:path withApplication:@"ABC.app"] == NO)
//    {
//        NSAlert *alert = [[NSAlert alloc] init];
//        [alert setMessageText:@"A.I.Segmentation plugin"];
//        [alert setInformativeText:@"Trying to open the file, ABC.app was not found."];
//        [alert runModal];
//        return;
//    }
//}




- (IBAction)showInfoWindow:(id)sender
{
    AIASInfoWindowController* infoWindow = [AIASPluginFilter getWindowControllerForNib:@"AIASInfoWindow"];
    if (infoWindow)
    {
        if ([[infoWindow window] isVisible])    [infoWindow close];
        else                                    [infoWindow showWindow:self];
    }
    else
    {
        infoWindow = [[AIASInfoWindowController alloc] loadInfoWin];
        if (infoWindow) [infoWindow showWindow:self];
    }

    if (infoWindow)
    {
        NSURL* url = [[NSBundle bundleForClass:self.class] URLForResource:@"info" withExtension:@"pdf"];
        PDFDocument* pdfDoc = url ? [[[PDFDocument alloc] initWithURL:url] autorelease] : nil;
        if (pdfDoc) [infoWindow.pdfView setDocument:pdfDoc];
    }
}




- (void) appendMessage:(NSString*)mes
{
    NSAttributedString *atrstr = [[[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@\n", mes]
                                                                  attributes:@{NSForegroundColorAttributeName:NSColor.whiteColor}] autorelease];
    NSTextView* txtv = MessageView.documentView;
    [txtv.textStorage beginEditing];
    [txtv.textStorage appendAttributedString:atrstr];
    [txtv.textStorage endEditing];
    [txtv scrollToEndOfDocument:self];
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.000001]];
}




- (void) appendError:(NSString*)mes error:(NSError*)errContent
{
    NSLog(@"AIAS error %@", mes);
    if (errContent)
    {
        NSLog(@"AIAS error description: %@", errContent.localizedDescription);
        NSLog(@"AIAS error reason: %@", errContent.localizedFailureReason);
    }

    [self appendMessage:mes];
    if (errContent)
    {
        [self appendMessage:[NSString stringWithFormat:@"Description: %@", errContent.localizedDescription]];
        [self appendMessage:[NSString stringWithFormat:@"Reason: %@", errContent.localizedFailureReason]];
    }
}




- (void) appendError:(NSString*)mes exception:(NSException*)exception
{
    NSLog(@"AIAS error %@", mes);
    if (exception)
    {
        NSLog(@"AIAS exception name: %@", exception.name);
        NSLog(@"AIAS exception reason: %@", exception.reason);
    }

    [self appendMessage:mes];
    if (exception)
    {
        [self appendMessage:[NSString stringWithFormat:@"Name: %@", exception.name]];
        [self appendMessage:[NSString stringWithFormat:@"Reason: %@", exception.reason]];
    }
}




- (void) appendError:(NSString*)mes
{
    [self appendError:mes error:nil];
}




@end


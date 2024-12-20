#import <AVFoundation/AVFoundation.h>

#include <libcam/vcap.hpp>
#include <libcam/utils.hpp>
#include "cap_delegate.hpp"
#include "../convert/convert.hpp"

namespace libcam {

    struct IVideoCaptureData {
        AVCaptureDevice *device;
        AVCaptureDeviceInput *capture_input;
        AVCaptureVideoDataOutput *capture_output;
        AVCaptureSession *capture_session;
        CaptureDelegate *capture_delegate;
    };

    VideoCapture::VideoCapture(size_t index) {
        @autoreleasepool {
            auto session = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[
                            AVCaptureDeviceTypeBuiltInWideAngleCamera,
                            AVCaptureDeviceTypeExternal]                   mediaType:AVMediaTypeVideo
                                                                                   position:AVCaptureDevicePositionBack];
            if (index >= session.devices.count) {
                throw VideoCaptureBadDeviceIndex(index);
            }
            NSError *error = nil;
            data = new IVideoCaptureData();
            IVideoCaptureData *data_ptr = static_cast<IVideoCaptureData *>(data);
            data_ptr->device = session.devices[index];
            data_ptr->capture_input = [[AVCaptureDeviceInput alloc] initWithDevice:data_ptr->device
                                                                             error:&error];
            if (error != nil) {
                throw VideoCaptureConfigurationError(
                        libcam::utils::format(
                                "Unable to configure input %s",
                                [error.localizedDescription UTF8String]
                        )
                );
            }
            data_ptr->capture_output = [[AVCaptureVideoDataOutput alloc] init];

            data_ptr->capture_output.alwaysDiscardsLateVideoFrames = YES;
            data_ptr->capture_delegate = [[CaptureDelegate alloc] init];

            OSType pixelFormat = 0;
            for (NSNumber *value in [data_ptr->capture_output availableVideoCVPixelFormatTypes]) {
                unsigned int format = [value intValue];
                if (pixel_format_is_supported(format)) {
                    pixelFormat = format;
                    break;
                }
            }
            if (!pixelFormat) {
                throw VideoCaptureConfigurationError("No available supported format");
            }
            NSDictionary *pixelBufferOptions = @{
                    (id) kCVPixelBufferPixelFormatTypeKey: @(pixelFormat)
            };
            data_ptr->capture_output.videoSettings = pixelBufferOptions;

            @autoreleasepool {
                dispatch_queue_t queue = dispatch_queue_create("camera_queue", DISPATCH_QUEUE_SERIAL);
                [data_ptr->capture_output setSampleBufferDelegate:data_ptr->capture_delegate
                                                            queue:queue];
            }

            data_ptr->capture_session = [[AVCaptureSession alloc] init];
            data_ptr->capture_session.sessionPreset = AVCaptureSessionPresetMedium;
            if ([data_ptr->capture_session canAddInput:data_ptr->capture_input]) {
                [data_ptr->capture_session addInput:data_ptr->capture_input];
            } else {
                throw VideoCaptureConfigurationError("Can't add capture input to capture session");
            }

            if ([data_ptr->capture_session canAddOutput:data_ptr->capture_output]) {
                [data_ptr->capture_session addOutput:data_ptr->capture_output];
            } else {
                throw VideoCaptureConfigurationError("Can't add output to capture session");
            }
            [data_ptr->capture_session startRunning];
            dispatch_semaphore_wait(data_ptr->capture_delegate->capture_started, DISPATCH_TIME_FOREVER);
        }
    }

    void VideoCapture::read(double timeout, RgbImage &result) {
        @autoreleasepool {
            NSDate *limit = [NSDate dateWithTimeIntervalSinceNow:timeout];
            if (![static_cast<IVideoCaptureData *>(data)->capture_delegate read:limit
                                                                         result:&result]) {
                throw VideoCaptureReadFrameTimeout();
            }
        }
    }

    std::vector<CaptureDeviceInfo> VideoCapture::list_devices() {
        @autoreleasepool {
            auto session = [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[
                            AVCaptureDeviceTypeBuiltInWideAngleCamera,
                            AVCaptureDeviceTypeExternal]                   mediaType:AVMediaTypeVideo
                                                                                   position:AVCaptureDevicePositionBack];
            std::vector<CaptureDeviceInfo> result(size_t(session.devices.count));
            for (size_t index = 0; index < result.size(); ++index) {
                result[index].index = index;
                result[index].name = [session.devices[index].localizedName UTF8String];
            }
            return result;
        }
    }

    VideoCapture::~VideoCapture() {
        if (data) {
            delete static_cast<IVideoCaptureData *>(data);
        }
    }

}

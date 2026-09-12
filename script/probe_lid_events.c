// Read-only probe for the lid-angle HID collection, not other HID devices.
#include <IOKit/hid/IOHIDManager.h>
#include <IOKit/hid/IOHIDKeys.h>
#include <CoreFoundation/CoreFoundation.h>
#include <stdio.h>
#include <stdlib.h>

static unsigned counts[256];
static int lastAngle = -1;
static CFAbsoluteTime started;
static void input(void *context, IOReturn result, void *sender,
                  IOHIDReportType type, uint32_t reportID, uint8_t *report, CFIndex length) {
    if (result != kIOReturnSuccess || reportID > 255) return;
    counts[reportID]++;
    int angle = reportID == 1 && length >= 3 ? report[1] | (report[2] << 8) : -1;
    if (counts[reportID] <= 12 || (angle >= 0 && angle != lastAngle)) {
        printf("EVENT t=%.3f report=%u bytes=", CFAbsoluteTimeGetCurrent()-started, reportID);
        for (CFIndex i=0; i<length && i<16; i++) printf("%02x",report[i]);
        printf("\n"); fflush(stdout);
    }
    if (angle >= 0) lastAngle = angle;
}
int main(int argc, char **argv) {
    int seconds = argc > 1 ? atoi(argv[1]) : 60;
    if (seconds < 1 || seconds > 120) return 2;
    IOHIDManagerRef manager = IOHIDManagerCreate(kCFAllocatorDefault,kIOHIDOptionsTypeNone);
    CFMutableDictionaryRef matching = CFDictionaryCreateMutable(NULL,0,&kCFTypeDictionaryKeyCallBacks,&kCFTypeDictionaryValueCallBacks);
    int page=0x20, usage=0x8a;
    CFNumberRef p=CFNumberCreate(NULL,kCFNumberIntType,&page), u=CFNumberCreate(NULL,kCFNumberIntType,&usage);
    CFDictionarySetValue(matching,CFSTR(kIOHIDDeviceUsagePageKey),p);
    CFDictionarySetValue(matching,CFSTR(kIOHIDDeviceUsageKey),u);
    IOHIDManagerSetDeviceMatching(manager,matching);
    CFRelease(matching);CFRelease(p);CFRelease(u);
    if (IOHIDManagerOpen(manager,kIOHIDOptionsTypeNone) != kIOReturnSuccess) return 1;
    CFSetRef devices = IOHIDManagerCopyDevices(manager);
    if (!devices || CFSetGetCount(devices)==0) { printf("No lid-angle device\n"); return 1; }
    const void **values = calloc((size_t)CFSetGetCount(devices), sizeof(*values));
    if (!values) return 1;
    CFSetGetValues(devices, values);
    IOHIDDeviceRef device = (IOHIDDeviceRef)values[0];
    free(values);
    if (IOHIDDeviceOpen(device,kIOHIDOptionsTypeNone)!=kIOReturnSuccess) return 1;
    CFArrayRef elements=IOHIDDeviceCopyMatchingElements(device,NULL,kIOHIDOptionsTypeNone);
    if (elements) {
        for (CFIndex i=0;i<CFArrayGetCount(elements);i++) {
            IOHIDElementRef e=(IOHIDElementRef)CFArrayGetValueAtIndex(elements,i);
            printf("ELEMENT report=%u type=%u usage=%x:%x bits=%u count=%u logical=%ld..%ld unit=%u exponent=%u\n",
                IOHIDElementGetReportID(e),IOHIDElementGetType(e),IOHIDElementGetUsagePage(e),IOHIDElementGetUsage(e),
                IOHIDElementGetReportSize(e),IOHIDElementGetReportCount(e),
                IOHIDElementGetLogicalMin(e),IOHIDElementGetLogicalMax(e),
                IOHIDElementGetUnit(e),IOHIDElementGetUnitExponent(e));
        }
        CFRelease(elements);
    }
    uint8_t buffer[64]={0};
    started=CFAbsoluteTimeGetCurrent();
    IOHIDDeviceRegisterInputReportCallback(device,buffer,sizeof(buffer),input,NULL);
    IOHIDDeviceScheduleWithRunLoop(device,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);
    printf("LISTENING %d seconds; no angle polling or device writes\n",seconds);fflush(stdout);
    CFRunLoopRunInMode(kCFRunLoopDefaultMode,seconds,false);
    for (unsigned i=0;i<256;i++) if (counts[i]) printf("COUNT report=%u events=%u\n",i,counts[i]);
    printf("FINISHED\n");
    IOHIDDeviceUnscheduleFromRunLoop(device,CFRunLoopGetCurrent(),kCFRunLoopDefaultMode);
    IOHIDDeviceRegisterInputReportCallback(device,buffer,sizeof(buffer),NULL,NULL);
    IOHIDDeviceClose(device,kIOHIDOptionsTypeNone);
    CFRelease(devices);
    IOHIDManagerClose(manager,kIOHIDOptionsTypeNone);CFRelease(manager);
    return 0;
}

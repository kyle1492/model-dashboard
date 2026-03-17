#ifndef ModelDashboard_Bridging_Header_h
#define ModelDashboard_Bridging_Header_h

#include <CoreFoundation/CoreFoundation.h>

// MARK: - Process inspection
#include <libproc.h>
#include <sys/sysctl.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/processor_info.h>
#include <mach/host_info.h>

// MARK: - Network
#include <ifaddrs.h>
#include <net/if.h>

// MARK: - IOReport (private framework for GPU metrics)
// These are private Apple APIs used by macmon/NeoAsitop — no sudo needed.
// Graceful degradation if unavailable.

typedef struct IOReportSubscriptionRef *IOReportSubscriptionRef;

CF_EXPORT CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef group, CFStringRef subgroup, uint64_t a, uint64_t b, uint64_t c);
CF_EXPORT IOReportSubscriptionRef IOReportCreateSubscription(void *a, CFMutableDictionaryRef desiredChannels, CFMutableDictionaryRef *subbedChannels, uint64_t channel_id, CFTypeRef b);
CF_EXPORT CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef sub, CFMutableDictionaryRef subbedChannels, CFTypeRef a);
CF_EXPORT CFDictionaryRef IOReportCreateSamplesDelta(CFDictionaryRef prev, CFDictionaryRef current, CFTypeRef a);

CF_EXPORT CFStringRef IOReportChannelGetGroup(CFDictionaryRef channel);
CF_EXPORT CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef channel);
CF_EXPORT CFStringRef IOReportChannelGetChannelName(CFDictionaryRef channel);
CF_EXPORT int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef channel, int64_t a);
CF_EXPORT int IOReportStateGetCount(CFDictionaryRef channel);
CF_EXPORT int64_t IOReportStateGetResidency(CFDictionaryRef channel, int index);
CF_EXPORT CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef channel, int index);

CF_EXPORT void IOReportIterate(CFDictionaryRef samples, int(^)(CFDictionaryRef channel));
CF_EXPORT void IOReportMergeChannels(CFMutableDictionaryRef dest, CFMutableDictionaryRef src, CFTypeRef a);

// MARK: - HID Sensor Hub
// Declared via @_silgen_name in TemperatureReader.swift to avoid Unmanaged issues.

#endif /* ModelDashboard_Bridging_Header_h */

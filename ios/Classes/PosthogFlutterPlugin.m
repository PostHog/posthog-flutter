#import "PosthogFlutterPlugin.h"
#import <PostHog/PHGPostHog.h>
#import <PostHog/PHGPostHogIntegration.h>
#import <PostHog/PHGContext.h>
#import <PostHog/PHGMiddleware.h>

@implementation PosthogFlutterPlugin
// Contents to be appended to the context
static NSDictionary *_appendToContextMiddleware;

+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  @try {
    NSString *path = [[NSBundle mainBundle] pathForResource: @"Info" ofType: @"plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile: path];
    NSString *writeKey = [dict objectForKey: @"com.posthog.posthog.API_KEY"];
    NSString *posthogHost = [dict objectForKey: @"com.posthog.posthog.POSTHOG_HOST"];
    BOOL captureApplicationLifecycleEvents = [[dict objectForKey: @"com.posthog.posthog.CAPTURE_APPLICATION_LIFECYCLE_EVENTS"] boolValue];
    PHGPostHogConfiguration *configuration = [PHGPostHogConfiguration configurationWithApiKey:writeKey host:posthogHost];

    // This middleware is responsible for manipulating only the context part of the request,
    // leaving all other fields as is.
    PHGMiddlewareBlock contextMiddleware = ^(PHGContext *_Nonnull context, PHGMiddlewareNext _Nonnull next) {
      // Do not execute if there is nothing to append
      if (_appendToContextMiddleware == nil) {
        next(context);
        return;
      }

      // Avoid overriding the context if there is none to override
      // (see different payload types here: https://github.com/posthogio/analytics-ios/tree/master/PostHog/Classes/Integrations)
      if (![context.payload isKindOfClass:[PHGCapturePayload class]]
        && ![context.payload isKindOfClass:[PHGScreenPayload class]]
        && ![context.payload isKindOfClass:[PHGIdentifyPayload class]]) {
        next(context);
        return;
      }

      next([context
        modify: ^(id<PHGMutableContext> _Nonnull ctx) {
          if (_appendToContextMiddleware == nil) {
            return;
          }

          // do not touch it if no payload is present
          if (ctx.payload == nil) {
            NSLog(@"Cannot update posthog context when the current context payload is empty.");
            return;
          }

          @try {
            // PHGPayload does not offer copyWith* methods, so we have to
            // manually test and re-create it for each of its type.
            if ([ctx.payload isKindOfClass:[PHGCapturePayload class]]) {
              ctx.payload = [[PHGCapturePayload alloc]
                initWithEvent: ((PHGCapturePayload*)ctx.payload).event
                properties: ((PHGCapturePayload*)ctx.payload).properties
              ];
            } else if ([ctx.payload isKindOfClass:[PHGScreenPayload class]]) {
              ctx.payload = [[PHGScreenPayload alloc]
                initWithName: ((PHGScreenPayload*)ctx.payload).name
                properties: ((PHGScreenPayload*)ctx.payload).properties
              ];
            } else if ([ctx.payload isKindOfClass:[PHGIdentifyPayload class]]) {
              ctx.payload = [[PHGIdentifyPayload alloc]
                initWithDistinctId: ((PHGIdentifyPayload*)ctx.payload).distinctId
                anonymousId: ((PHGIdentifyPayload*)ctx.payload).anonymousId
                properties: ((PHGIdentifyPayload*)ctx.payload).properties
              ];
            }
          }
          @catch (NSException *exception) {
            NSLog(@"Could not update posthog context: %@", [exception reason]);
          }
        }]
      );
    };

    configuration.middlewares = @[
      [[PHGBlockMiddleware alloc] initWithBlock:contextMiddleware]
    ];

    configuration.captureApplicationLifecycleEvents = captureApplicationLifecycleEvents;

    [PHGPostHog setupWithConfiguration:configuration];
    FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"posthogflutter"
      binaryMessenger:[registrar messenger]];
    PosthogFlutterPlugin* instance = [[PosthogFlutterPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];
  }
  @catch (NSException *exception) {
    NSLog(@"%@", [exception reason]);
  }
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"identify" isEqualToString:call.method]) {
    [self identify:call result:result];
  } else if ([@"capture" isEqualToString:call.method]) {
    [self capture:call result:result];
  } else if ([@"screen" isEqualToString:call.method]) {
    [self screen:call result:result];
  } else if ([@"alias" isEqualToString:call.method]) {
    [self alias:call result:result];
  } else if ([@"getAnonymousId" isEqualToString:call.method]) {
    [self anonymousId:result];
  } else if ([@"reset" isEqualToString:call.method]) {
    [self reset:result];
  } else if ([@"disable" isEqualToString:call.method]) {
    [self disable:result];
  } else if ([@"enable" isEqualToString:call.method]) {
    [self enable:result];
  } else if ([@"debug" isEqualToString:call.method]) {
    [self debug:call result:result];
  } else if ([@"setContext" isEqualToString:call.method]) {
    [self setContext:call result:result];
  } else if ([@"isFeatureEnabled" isEqualToString:call.method]) {
    [self isFeatureEnabled:call result:result];
  } else if ([@"reloadFeatureFlags" isEqualToString:call.method]) {
    [self reloadFeatureFlags:call result:result];
  } else {
    result(FlutterMethodNotImplemented);
  }
}

- (void)isFeatureEnabled:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSString *key = call.arguments[@"key"];

    BOOL *isFeatureEnabledResult = [[PHGPostHog sharedPostHog] isFeatureEnabled: key];
    result([NSNumber numberWithBool:isFeatureEnabledResult]);
  }
  @catch (NSException *exception) {
    result([FlutterError
      errorWithCode:@"PosthogFlutterException"
      message:[exception reason]
      details: nil]);
  }
}

- (void)reloadFeatureFlags:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    [[PHGPostHog sharedPostHog] reloadFeatureFlags];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"PosthogFlutterException" message:[exception reason] details: nil]);
  }
}

- (void)setContext:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSDictionary *context = call.arguments[@"context"];
    _appendToContextMiddleware = context;
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError
      errorWithCode:@"PosthogFlutterException"
      message:[exception reason]
      details: nil]);
  }

}

- (void)identify:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSString *userId = call.arguments[@"userId"];
    NSDictionary *properties = call.arguments[@"properties"];
    NSDictionary *options = call.arguments[@"options"];
    [[PHGPostHog sharedPostHog] identify: userId
                      properties: properties 
                     options: options];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError
      errorWithCode:@"PosthogFlutterException"
      message:[exception reason]
      details: nil]);
  }
}

- (void)capture:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSString *eventName = call.arguments[@"eventName"];
    NSDictionary *properties = call.arguments[@"properties"];
    NSDictionary *options = call.arguments[@"options"];
    [[PHGPostHog sharedPostHog] capture: eventName
                    properties: properties];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"PosthogFlutterException" message:[exception reason] details: nil]);
  }
}

- (void)screen:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSString *screenName = call.arguments[@"screenName"];
    NSDictionary *properties = call.arguments[@"properties"];
    NSDictionary *options = call.arguments[@"options"];
    [[PHGPostHog sharedPostHog] screen: screenName
                  properties: properties];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"PosthogFlutterException" message:[exception reason] details: nil]);
  }
}

- (void)alias:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    NSString *alias = call.arguments[@"alias"];
    NSDictionary *options = call.arguments[@"options"];
    [[PHGPostHog sharedPostHog] alias: alias];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"PosthogFlutterException" message:[exception reason] details: nil]);
  }
}

- (void)anonymousId:(FlutterResult)result {
  @try {
    NSString *anonymousId = [[PHGPostHog sharedPostHog] getAnonymousId];
    result(anonymousId);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"PosthogFlutterException" message:[exception reason] details: nil]);
  }
}

- (void)reset:(FlutterResult)result {
  @try {
    [[PHGPostHog sharedPostHog] reset];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"PosthogFlutterException" message:[exception reason] details: nil]);
  }
}

- (void)disable:(FlutterResult)result {
  @try {
    [[PHGPostHog sharedPostHog] disable];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"PosthogFlutterException" message:[exception reason] details: nil]);
  }
}

- (void)enable:(FlutterResult)result {
  @try {
    [[PHGPostHog sharedPostHog] enable];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"PosthogFlutterException" message:[exception reason] details: nil]);
  }
}

- (void)debug:(FlutterMethodCall*)call result:(FlutterResult)result {
  @try {
    BOOL enabled = call.arguments[@"debug"];
    [PHGPostHog debug: enabled];
    result([NSNumber numberWithBool:YES]);
  }
  @catch (NSException *exception) {
    result([FlutterError errorWithCode:@"PosthogFlutterException" message:[exception reason] details: nil]);
  }
}

+ (NSDictionary *) mergeDictionary: (NSDictionary *) first with: (NSDictionary *) second {
  NSMutableDictionary *result = [first mutableCopy];
  [second enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
    id contained = [result objectForKey:key];
    if (!contained) {
      [result setObject:value forKey:key];
    } else if ([value isKindOfClass:[NSDictionary class]]) {
      [result setObject:[PosthogFlutterPlugin mergeDictionary:result[key] with:value]
        forKey:key];
    }
  }];
  return result;
}

@end

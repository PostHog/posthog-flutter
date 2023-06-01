package com.posthog.posthog_flutter;

import androidx.annotation.NonNull;

import android.app.Activity;
import android.content.Context;
import android.content.pm.ApplicationInfo;
import android.content.pm.PackageManager;
import android.content.SharedPreferences;
import android.os.Bundle;
import android.util.Log;

import com.posthog.android.PostHog;
import com.posthog.android.PostHogContext;
import com.posthog.android.Properties;
import com.posthog.android.Options;
import com.posthog.android.Middleware;
import com.posthog.android.payloads.BasePayload;
import static com.posthog.android.PostHog.LogLevel;

import java.util.LinkedHashMap;
import java.util.HashMap;
import java.util.Map;

import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.MethodChannel.MethodCallHandler;
import io.flutter.plugin.common.MethodChannel.Result;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.embedding.engine.plugins.FlutterPlugin;

/** PosthogFlutterPlugin */
public class PosthogFlutterPlugin implements MethodCallHandler, FlutterPlugin {
  private Context applicationContext;
  private MethodChannel methodChannel;

  static HashMap<String, Object> appendToContextMiddleware;

  /** Plugin registration. */
  public static void registerWith(PluginRegistry.Registrar registrar) {
    final PosthogFlutterPlugin instance = new PosthogFlutterPlugin();
    instance.setupChannels(registrar.context(), registrar.messenger());
  }

  @Override
  public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
    setupChannels(binding.getApplicationContext(), binding.getBinaryMessenger());
  }

  private void setupChannels(Context applicationContext, BinaryMessenger messenger) {
    try {
      methodChannel = new MethodChannel(messenger, "posthogflutter");
      this.applicationContext = applicationContext;

      ApplicationInfo ai = applicationContext.getPackageManager()
        .getApplicationInfo(applicationContext.getPackageName(), PackageManager.GET_META_DATA);

      Bundle bundle = ai.metaData;

      String writeKey = bundle.getString("com.posthog.posthog.API_KEY");
      String posthogHost = bundle.getString("com.posthog.posthog.POSTHOG_HOST");
      Boolean captureApplicationLifecycleEvents = bundle.getBoolean("com.posthog.posthog.TRACK_APPLICATION_LIFECYCLE_EVENTS");
      Boolean debug = bundle.getBoolean("com.posthog.posthog.DEBUG", false);

      PostHog.Builder posthogBuilder = new PostHog.Builder(applicationContext, writeKey, posthogHost);
      if (captureApplicationLifecycleEvents) {
        // Enable this to record certain application events automatically
        posthogBuilder.captureApplicationLifecycleEvents();
      }

      if (debug) {
        posthogBuilder.logLevel(LogLevel.DEBUG);
      }

      // Here we build a middleware that just appends data to the current context
      // using the [deepMerge] strategy.
      posthogBuilder.middleware(
        new Middleware() {
          @Override
          public void intercept(Chain chain) {
            try {
              if (appendToContextMiddleware == null) {
                chain.proceed(chain.payload());
                return;
              }

              BasePayload payload = chain.payload();
              BasePayload newPayload = payload.toBuilder()
                .context(appendToContextMiddleware)
                .build();

              chain.proceed(newPayload);
            } catch (Exception e) {
              Log.e("PosthogFlutter", e.getMessage());
              chain.proceed(chain.payload());
            }
          }
        }
      );

      // Set the initialized instance as globally accessible.
      // It may throw an exception if we are trying to re-register a singleton PostHog instance.
      // This state may happen after the app is popped (back button until the app closes)
      // and opened again from the TaskManager.
      try {
        PostHog.setSingletonInstance(posthogBuilder.build());
      } catch (IllegalStateException e) {
        Log.w("PosthogFlutter", e.getMessage());
      }
      // register the channel to receive calls
      methodChannel.setMethodCallHandler(this);
    } catch (Exception e) {
      Log.e("PosthogFlutter", e.getMessage());
    }
  }

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) { }

  @Override
  public void onMethodCall(MethodCall call, Result result) {
    if(call.method.equals("identify")) {
      this.identify(call, result);
    } else if (call.method.equals("capture")) {
      this.capture(call, result);
    } else if (call.method.equals("screen")) {
      this.screen(call, result);
    } else if (call.method.equals("alias")) {
      this.alias(call, result);
    } else if (call.method.equals("getAnonymousId")) {
      this.anonymousId(result);
    } else if (call.method.equals("reset")) {
      this.reset(result);
    } else if (call.method.equals("setContext")) {
      this.setContext(call, result);
    } else if (call.method.equals("disable")) {
      this.disable(call, result);
    } else if (call.method.equals("enable")) {
      this.enable(call, result);
    } else if (call.method.equals("isFeatureEnabled")) {
      this.isFeatureEnabled(call, result);
    } else if (call.method.equals("reloadFeatureFlags")) {
      this.reloadFeatureFlags(call, result);
    } else if (call.method.equals("group")) {
      this.reloadFeatureFlags(call, result);
    } else {
      result.notImplemented();
    }
  }

  private Properties hashMapToProperties(HashMap<String, Object> propertiesData) {
    Properties properties = new Properties();

    for(Map.Entry<String, Object> property : propertiesData.entrySet()) {
      String key = property.getKey();
      Object value = property.getValue();
      properties.putValue(key, value);
    }

    return properties;
  }

  private void identify(MethodCall call, Result result) {
    try {
      String userId = call.argument("userId");
      HashMap<String, Object> propertiesData = call.argument("properties");
      HashMap<String, Object> optionsData = call.argument("options");
      Properties properties = this.hashMapToProperties(propertiesData);
      Options options = this.buildOptions(optionsData);
      PostHog.with(this.applicationContext).identify(userId, properties, options);

      result.success(true);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }

  private void capture(MethodCall call, Result result) {
    try {
      String eventName = call.argument("eventName");
      HashMap<String, Object> propertiesData = call.argument("properties");
      HashMap<String, Object> optionsData = call.argument("options");
      Properties properties = this.hashMapToProperties(propertiesData);
      Options options = this.buildOptions(optionsData);

      PostHog.with(this.applicationContext).capture(eventName, properties, options);
      result.success(true);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }

  private void screen(MethodCall call, Result result) {
    try {
      String screenName = call.argument("screenName");
      HashMap<String, Object> propertiesData = call.argument("properties");
      HashMap<String, Object> optionsData = call.argument("options");
      Properties properties = this.hashMapToProperties(propertiesData);
      Options options = this.buildOptions(optionsData);

      PostHog.with(this.applicationContext).screen(screenName, properties, options);
      result.success(true);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }

  private void alias(MethodCall call, Result result) {
    try {
      String alias = call.argument("alias");
      HashMap<String, Object> optionsData = call.argument("options");
      Options options = this.buildOptions(optionsData);
      PostHog.with(this.applicationContext).alias(alias, options);
      result.success(true);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }

  private void anonymousId(Result result) {
    try {
      String anonymousId = PostHog.with(this.applicationContext).getAnonymousId();
      result.success(anonymousId);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }

  private void reset(Result result) {
    try {
      PostHog.with(this.applicationContext).reset();
      result.success(true);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }

  private void setContext(MethodCall call, Result result) {
    try {
      this.appendToContextMiddleware = call.argument("context");
      result.success(true);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }

  // There is no enable method at this time for PostHog on Android.
  // Instead, we use optOut as a proxy to achieve the same result.
  private void enable(MethodCall call, Result result) {
    try {
      PostHog.with(this.applicationContext).optOut(false);
      result.success(true);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }

  // There is no disable method at this time for PostHog on Android.
  // Instead, we use optOut as a proxy to achieve the same result.
  private void disable(MethodCall call, Result result) {
    try {
      PostHog.with(this.applicationContext).optOut(true);
      result.success(true);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }

  private void isFeatureEnabled(MethodCall call, Result result) {
    try {
      String key = call.argument("key");
      boolean isEnabled = PostHog.with(this.applicationContext).isFeatureEnabled(key);
      result.success(isEnabled);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }

  private void reloadFeatureFlags(MethodCall call, Result result) {
    try {
      PostHog.with(this.applicationContext).reloadFeatureFlags();
      result.success(true);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }

  private void group(MethodCall call, Result result) {
    try {
      String groupType = call.argument("groupType");
      String groupKey = call.argument("groupKey");
      HashMap<String, Object> propertiesData = call.argument("groupProperties");
      Properties properties = this.hashMapToProperties(propertiesData);

      PostHog.with(this.applicationContext).group(groupType, groupKey, properties);
      result.success(true);
    } catch (Exception e) {
      result.error("PosthogFlutterException", e.getLocalizedMessage(), null);
    }
  }
  /**
   * Enables / disables / sets custom integration properties so Posthog can properly
   * interact with 3rd parties, such as Amplitude.
   * @see https://posthog.com/docs/connections/sources/catalog/libraries/mobile/android/#selecting-destinations
   * @see https://github.com/posthogio/posthog-android/blob/master/posthog/src/main/java/com/posthog.android/Options.java
   */
  @SuppressWarnings("unchecked")
  private Options buildOptions(HashMap<String, Object> optionsData) {
    Options options = new Options();
    return options;
  }

  // Merges [newMap] into [original], *not* preserving [original]
  // keys (deep) in case of conflicts.
  private static Map deepMerge(Map original, Map newMap) {
    for (Object key : newMap.keySet()) {
      if (newMap.get(key) instanceof Map && original.get(key) instanceof Map) {
        Map originalChild = (Map) original.get(key);
        Map newChild = (Map) newMap.get(key);
        original.put(key, deepMerge(originalChild, newChild));
      } else {
        original.put(key, newMap.get(key));
      }
    }
    return original;
  }
}

#ifndef RUNNER_DESKTOP_LOG_BRIDGE_H_
#define RUNNER_DESKTOP_LOG_BRIDGE_H_

#include <flutter/event_channel.h>
#include <flutter/event_stream_handler_functions.h>
#include <flutter/standard_method_codec.h>

#include <memory>
#include <string>
#include <vector>

class DesktopLogBridge {
 public:
  static DesktopLogBridge& GetInstance();

  void Attach(flutter::BinaryMessenger* messenger);
  void Emit(const std::string& level,
            const std::string& source,
            const std::string& message);

 private:
  DesktopLogBridge() = default;

  using EncodableValue = flutter::EncodableValue;
  using EncodableMap = flutter::EncodableMap;
  using EventChannel = flutter::EventChannel<EncodableValue>;
  using EventSink = flutter::EventSink<EncodableValue>;

  EncodableValue MakePayload(const std::string& level,
                             const std::string& source,
                             const std::string& message) const;
  void FlushBuffer();

  std::unique_ptr<EventChannel> channel_;
  std::unique_ptr<EventSink> sink_;
  std::vector<EncodableValue> buffer_;
};

#endif  // RUNNER_DESKTOP_LOG_BRIDGE_H_

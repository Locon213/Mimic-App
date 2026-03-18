#include "desktop_log_bridge.h"

#include <chrono>

DesktopLogBridge& DesktopLogBridge::GetInstance() {
  static DesktopLogBridge instance;
  return instance;
}

void DesktopLogBridge::Attach(flutter::BinaryMessenger* messenger) {
  if (channel_) {
    return;
  }

  channel_ = std::make_unique<EventChannel>(
      messenger, "com.locon213.mimic_app/native_logs",
      &flutter::StandardMethodCodec::GetInstance());

  auto handler =
      std::make_unique<flutter::StreamHandlerFunctions<EncodableValue>>(
          [this](const EncodableValue* arguments,
                 std::unique_ptr<EventSink> &&events)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            sink_ = std::move(events);
            FlushBuffer();
            return nullptr;
          },
          [this](const EncodableValue* arguments)
              -> std::unique_ptr<flutter::StreamHandlerError<EncodableValue>> {
            sink_.reset();
            return nullptr;
          });

  channel_->SetStreamHandler(std::move(handler));
}

void DesktopLogBridge::Emit(const std::string& level,
                            const std::string& source,
                            const std::string& message) {
  auto payload = MakePayload(level, source, message);
  if (sink_) {
    sink_->Success(payload);
    return;
  }

  buffer_.push_back(payload);
  if (buffer_.size() > 200) {
    buffer_.erase(buffer_.begin(),
                  buffer_.begin() + static_cast<long>(buffer_.size() - 200));
  }
}

DesktopLogBridge::EncodableValue DesktopLogBridge::MakePayload(
    const std::string& level,
    const std::string& source,
    const std::string& message) const {
  const auto timestamp = std::chrono::duration_cast<std::chrono::milliseconds>(
                             std::chrono::system_clock::now().time_since_epoch())
                             .count();

  EncodableMap payload;
  payload[EncodableValue("level")] = EncodableValue(level);
  payload[EncodableValue("source")] = EncodableValue(source);
  payload[EncodableValue("message")] = EncodableValue(message);
  payload[EncodableValue("timestamp")] =
      EncodableValue(static_cast<int64_t>(timestamp));
  return EncodableValue(payload);
}

void DesktopLogBridge::FlushBuffer() {
  if (!sink_) {
    return;
  }

  for (const auto& payload : buffer_) {
    sink_->Success(payload);
  }
  buffer_.clear();
}

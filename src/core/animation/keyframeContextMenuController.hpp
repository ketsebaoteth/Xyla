#pragma once

#include "animChannel.hpp"
#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <vector>

namespace xyla {
class TimelineModel;
}

namespace xyla::anim {

enum class MergeMode { Mix, OverwriteRange, OverwriteAll };

enum class HandleType { Free, Vector, Aligned, Auto, AutoClamped };

enum class EasingType { Linear, EaseIn, EaseOut, EaseInOut };

enum class ExtrapolationMode { Constant, Linear, Cycle, CycleWithOffset };

struct ClipboardKeyframe {
  QString propId;
  QString clipId;
  int64_t frame{0};
  float value{0.0f};
  int interpolation{1};
  float inX{0.666f};
  float inY{0.0f};
  float outX{0.333f};
  float outY{0.0f};
};

struct ClipboardBuffer {
  int64_t earliestFrame{0};
  int64_t latestFrame{0};
  std::vector<ClipboardKeyframe> keys;

  [[nodiscard]] bool isEmpty() const noexcept { return keys.empty(); }
  void clear() noexcept {
    keys.clear();
    earliestFrame = 0;
    latestFrame = 0;
  }
};

class KeyframeContextMenuController : public QObject {
  Q_OBJECT
  Q_PROPERTY(bool hasClipboard READ hasClipboard NOTIFY clipboardChanged)

public:
  explicit KeyframeContextMenuController(QObject *parent = nullptr);

  Q_INVOKABLE void muteChannel(QObject *modelObj, const QString &clipId,
                               const QString &propId, bool mute);

  Q_INVOKABLE void lockChannel(QObject *modelObj, const QString &clipId,
                               const QString &propId, bool lock);
  [[nodiscard]] bool hasClipboard() const noexcept {
    return !m_clipboard.isEmpty();
  }

  Q_INVOKABLE void copy(QObject *model, const QVariantList &selectedKeys);
  Q_INVOKABLE void paste(QObject *model, int64_t playheadFrame);
  Q_INVOKABLE void pasteNoOffset(QObject *model);
  Q_INVOKABLE void pasteOverwriteRange(QObject *model, int64_t playheadFrame);
  Q_INVOKABLE void pasteOverwriteAll(QObject *model, int64_t playheadFrame);

  Q_INVOKABLE void setInterpolation(QObject *model,
                                    const QVariantList &selectedKeys,
                                    int interpMode);
  Q_INVOKABLE void setHandleType(QObject *model,
                                 const QVariantList &selectedKeys,
                                 int handleTypeInt);
  Q_INVOKABLE void setEasing(QObject *model, const QVariantList &selectedKeys,
                             int easingTypeInt);

  Q_INVOKABLE void cleanKeys(QObject *model, const QVariantList &selectedKeys,
                             float tolerance = 0.001f);
  Q_INVOKABLE void sampleKeys(QObject *model, const QVariantList &selectedKeys);
  Q_INVOKABLE void bakeCurve(QObject *model, const QString &clipId,
                             const QString &propId);
  Q_INVOKABLE void deleteKeys(QObject *model, const QVariantList &selectedKeys);

  Q_INVOKABLE void setExtrapolation(QObject *model, const QString &clipId,
                                    const QString &propId, int modeInt);

signals:
  void clipboardChanged();

private:
  void executePaste(TimelineModel *model, int64_t playheadFrame, MergeMode mode,
                    bool useOffset);

  ClipboardBuffer m_clipboard;
};

} // namespace xyla::anim

#pragma once

#include <cstdint>
#include <vector>

#include <QString>

#include "core/animation/keyframe.hpp"
#include "core/undo/xylaCommand.hpp"

namespace xyla {
class TimelineModel;
}

namespace xyla::anim {

/**
 * @brief Atomic undo command deleting one or more animation keyframes from clip
 * properties.
 */
class DeleteKeyframesCommand : public xyla::XylaCommand {
public:
  struct KeyframeRecord {
    QString clipId;
    QString propId;
    int64_t absFrame{0};
    int64_t relFrame{0};
    float value{0.0f};
    anim::Interpolation interpolation{anim::Interpolation::Linear};
    anim::BezierHandles bezier{};
  };

  DeleteKeyframesCommand(xyla::TimelineModel *model,
                         std::vector<KeyframeRecord> records);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override;

private:
  xyla::TimelineModel *m_model{nullptr};
  std::vector<KeyframeRecord> m_records;
};

/**
 * @brief Atomic undo command translating keyframe points across timeline
 * frames.
 */
class MoveKeyframesCommand : public xyla::XylaCommand {
public:
  struct MoveRecord {
    QString clipId;
    QString propId;
    int64_t oldAbsFrame{0};
    int64_t newAbsFrame{0};
    int64_t oldRelFrame{0};
    int64_t newRelFrame{0};
  };

  MoveKeyframesCommand(xyla::TimelineModel *model,
                       std::vector<MoveRecord> moves);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override;

private:
  xyla::TimelineModel *m_model{nullptr};
  std::vector<MoveRecord> m_moves;
};

/**
 * @brief Atomic undo command pasting keyframes and tracking overwritten
 * collision states.
 */
class PasteKeyframesCommand : public xyla::XylaCommand {
public:
  struct KeyRecord {
    QString clipId;
    QString propId;
    int64_t relFrame{0};
    float value{0.0f};
    anim::Interpolation interpolation{anim::Interpolation::Linear};
    anim::BezierHandles bezier{};
  };

  PasteKeyframesCommand(xyla::TimelineModel *model,
                        std::vector<KeyRecord> pastedKeys,
                        std::vector<KeyRecord> overwrittenKeys);

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override { return "Paste Keyframes"; }

private:
  xyla::TimelineModel *m_model{nullptr};
  std::vector<KeyRecord> m_pastedKeys;
  std::vector<KeyRecord> m_overwrittenKeys;
};

/**
 * @brief Atomic undo command modifying values, tangents, or interpolation on
 * keyframes.
 */
class UpdateKeyframeCommand : public xyla::XylaCommand {
public:
  struct KeyframeState {
    int64_t relFrame{0};
    float value{0.0f};
    anim::Interpolation interpolation{anim::Interpolation::Linear};
    anim::BezierHandles bezier{};
  };

  struct Record {
    QString clipId;
    QString propId;
    KeyframeState oldState;
    KeyframeState newState;
  };

  UpdateKeyframeCommand(xyla::TimelineModel *model, std::vector<Record> records,
                        QString description = "Adjust Keyframe");

  void undo() override;
  void redo() override;
  [[nodiscard]] QString text() const override { return m_description; }

private:
  void applyState(const Record &rec, const KeyframeState &from,
                  const KeyframeState &to);

  xyla::TimelineModel *m_model{nullptr};
  std::vector<Record> m_records;
  QString m_description;
};

} // namespace xyla::anim

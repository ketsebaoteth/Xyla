#pragma once

#include "animMath.hpp"
#include "keyframe.hpp"

#include <algorithm>
#include <vector>

namespace xyla::anim {

class AnimProperty {
public:
  AnimProperty() = default;
  explicit AnimProperty(float staticValue) : m_staticValue(staticValue) {}

  [[nodiscard]] float evaluate(FrameIndex frame) const noexcept {
    // If MUTED, hold static value and bypass keyframe animation
    if (m_isMuted || !m_isAnimated || m_keys.empty())
      return m_staticValue;

    if (frame <= m_keys.front().frame)
      return m_keys.front().value;
    if (frame >= m_keys.back().frame)
      return m_keys.back().value;

    auto it = std::lower_bound(m_keys.begin(), m_keys.end(), frame);
    if (it != m_keys.end() && it->frame == frame)
      return it->value;

    const size_t right = static_cast<size_t>(std::distance(m_keys.begin(), it));
    const size_t left = right - 1;
    const Keyframe<float> &k0 = m_keys[left];
    const Keyframe<float> &k1 = m_keys[right];

    if (k0.interpolation == Interpolation::Hold)
      return k0.value;

    const float tNorm = static_cast<float>(frame - k0.frame) /
                        static_cast<float>(k1.frame - k0.frame);

    if (k0.interpolation == Interpolation::Linear)
      return lerp(k0.value, k1.value, tNorm);

    // Bezier
    const float t = solveBezierT(tNorm, k0.bezier.outX, k1.bezier.inX);
    const float y = evalBezierY(t, k0.bezier.outY, 1.0f + k1.bezier.inY);
    return lerp(k0.value, k1.value, y);
  }

  void setStaticValue(float v) noexcept { m_staticValue = v; }
  [[nodiscard]] float staticValue() const noexcept { return m_staticValue; }

  [[nodiscard]] bool isAnimated() const noexcept { return m_isAnimated; }

  // ── Channel State ──────────────────────────────────────────
  [[nodiscard]] bool isMuted() const noexcept { return m_isMuted; }
  void setMuted(bool m) noexcept { m_isMuted = m; }

  [[nodiscard]] bool isLocked() const noexcept { return m_isLocked; }
  void setLocked(bool l) noexcept { m_isLocked = l; }
  // ───────────────────────────────────────────────────────────

  [[nodiscard]] bool hasKeyframe(FrameIndex frame) const noexcept {
    for (const auto &k : m_keys) {
      if (k.frame == frame)
        return true;
    }
    return false;
  }

  [[nodiscard]] const Keyframe<float> *
  findKeyframe(FrameIndex frame) const noexcept {
    for (const auto &k : m_keys) {
      if (k.frame == frame)
        return &k;
    }
    return nullptr;
  }

  void setKeyframe(FrameIndex frame, float value,
                   Interpolation interp = Interpolation::Linear,
                   BezierHandles bezier = {}) {
    if (m_isLocked)
      return; // Locked channels cannot receive keyframe updates

    m_isAnimated = true;
    auto it = std::lower_bound(m_keys.begin(), m_keys.end(), frame);
    if (it != m_keys.end() && it->frame == frame) {
      it->value = value;
      it->interpolation = interp;
      it->bezier = bezier;
    } else {
      m_keys.insert(it, Keyframe<float>{frame, value, interp, bezier});
    }
  }

  bool removeKeyframe(FrameIndex frame) noexcept {
    if (m_isLocked)
      return false;

    for (auto it = m_keys.begin(); it != m_keys.end(); ++it) {
      if (it->frame == frame) {
        m_keys.erase(it);
        if (m_keys.empty())
          m_isAnimated = false;
        return true;
      }
    }
    return false;
  }

  bool moveKeyframe(FrameIndex oldFrame, FrameIndex newFrame) {
    if (m_isLocked || oldFrame == newFrame)
      return false;

    auto it = std::lower_bound(m_keys.begin(), m_keys.end(), oldFrame);
    if (it == m_keys.end() || it->frame != oldFrame)
      return false;

    Keyframe<float> key = *it;
    m_keys.erase(it);
    key.frame = newFrame;
    setKeyframe(key.frame, key.value, key.interpolation, key.bezier);
    return true;
  }

  void clearKeyframes() noexcept {
    if (m_isLocked)
      return;
    m_keys.clear();
    m_isAnimated = false;
  }

  [[nodiscard]] const std::vector<Keyframe<float>> &keyframes() const noexcept {
    return m_keys;
  }

  [[nodiscard]] std::vector<FrameIndex> keyframeFrames() const {
    std::vector<FrameIndex> frames;
    frames.reserve(m_keys.size());
    for (const auto &k : m_keys)
      frames.push_back(k.frame);
    return frames;
  }

private:
  float m_staticValue{0.0f};
  bool m_isAnimated{false};
  bool m_isMuted{false};
  bool m_isLocked{false};
  std::vector<Keyframe<float>> m_keys;
};

} // namespace xyla::anim

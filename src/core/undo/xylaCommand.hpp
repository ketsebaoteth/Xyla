#pragma once

#include <QString>
#include <QUndoCommand>

namespace xyla {

/**
 * @brief Base command class for all undoable and redoable timeline and
 * workspace actions.
 *
 * Inherits from QUndoCommand to provide macro bundling, command compression,
 * and undo stack integration.
 *
 * @note Derived commands must implement undo() and redo() symmetrically.
 */
class XylaCommand : public QUndoCommand {
public:
  /**
   * @brief Construct a command with a display action label.
   *
   * @param text Human-readable description shown in undo/redo menus.
   * @param parent Optional parent command for command tree hierarchies.
   */
  explicit XylaCommand(const QString &text = QString(),
                       QUndoCommand *parent = nullptr)
      : QUndoCommand(text, parent) {}

  ~XylaCommand() override = default;

  /**
   * @brief Retrieve display text describing the action.
   *
   * @return Action description string.
   */
  [[nodiscard]] virtual QString text() const { return QUndoCommand::text(); }
};

} // namespace xyla

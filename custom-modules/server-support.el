;;; server-support.el --- Daemon-aware server-start; launch via emacs-daemon-wrapper. -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Simon Watson
;; SPDX-License-Identifier: MIT

;; Author: Simon Watson

;;; Commentary:

;; Daemon-aware `server-start' and simple client-frame helpers.  Launch
;; Emacs via `emacs-daemon-wrapper' on `PATH' (external repo
;; simonsjw/emacs-daemon-wrapper); do not import that wrapper into this
;; tree.  Load from `init.el' after `logging-config'.
;;
;; Map:
;;   Feature:    server-support
;;   Load-after: path-support logging-config
;;   Load-phase: startup
;;   Keymaps:    none
;;   Docs:       docs/server-support.org
;;   OS:         emacs-daemon-wrapper
;;
;; | Action                         | Effect with one client frame                                                        |
;; ------------------------------------------------------------------------------------------------------------------------
;; | Window-manager close / C-x 5 0 | Deletes that frame; daemon stays up                                                 |
;; | C-x C-c                        | Deletes that client frame; daemon stays up                                          |
;; | C-x #                          | Marks the server buffer done; may delete the client frame if this client is waiting |
;; | M-x kill-emacs                 | Stops the daemon                                                                    |

;;; Code:

(require 'path-support)
(require 'logging-config)
(log/debug :fn 'server-support
           :msg "Starting load of the server-support module."
           :obj t)
;; ----------------------------------------------------------------------
;; 1. Start server
;; ----------------------------------------------------------------------
(defun my-server/start-if-not-running ()
  "Start the Emacs server if it is not already running.

Efficiency: short-circuit early using `server-running-p'.
Works identically in normal and --fg-daemon sessions.
Historical note: redundant `server-start' calls were a common cause of
warnings in systemd user units pre-2024."
  (when (and (fboundp 'server-running-p)
             (not (server-running-p)))
    (server-start)
    (log/info :fn 'my-server/start-if-not-running
              :msg "Emacs server started."
              :obj t)
    ))

(my-server/start-if-not-running)

;; ----------------------------------------------------------------------
;; 2. Simple client frame creator (clean, no face resets)
;; ----------------------------------------------------------------------
(defun my-server/simple-client-frame-p (frame)
  "Return non-nil if FRAME is a graphical non-IDE frame."
  (and (frame-live-p frame)
       (display-graphic-p frame)
       (not (eq (frame-parameter frame 'UI-TYPE) 'IDE))))

(defun my-server/display-simple-frame (buffer)
  "Display BUFFER in a simple, single-window client frame.

Reuse the frame `emacsclient -c' already created.  Only call
`make-frame' when the selected frame is an IDE frame or is not
graphical, so a second client invocation cannot inherit the IDE
layout."
  (let* ((reuse (and (my-server/simple-client-frame-p (selected-frame))
                     (selected-frame)))
         (frame (or reuse
                    (make-frame '((UI-TYPE . nil)
                                  (custom-window-management . nil)
                                  (name . "Simple Client Frame")
                                  (width . 120)
                                  (height . 40)))))
         (win (frame-selected-window frame)))
    (select-frame-set-input-focus frame)
    (set-frame-parameter frame 'UI-TYPE nil)
    (set-frame-parameter frame 'custom-window-management nil)
    (set-frame-parameter frame 'name "Simple Client Frame")
    (set-window-buffer win buffer)
    (set-window-prev-buffers win nil)
    (set-window-next-buffers win nil)
    (delete-other-windows win)
    (condition-case err
        (my-visual/apply-all-customisations)
      (error
       (log/error :fn 'my-server/display-simple-frame
                  :msg "Visual apply failed (non-fatal)."
                  :obj err)))
    (delete-other-windows)
    (set-window-buffer (selected-window) buffer)
    (log/info :fn 'my-server/display-simple-frame
              :msg (if reuse
                       "Reused existing client frame."
                     "Created simple client frame.")
              :obj (buffer-name buffer))
    (selected-window)))

;; Wire it in — this is what makes `emacsclient -c` use the simple frame
(setq server-window #'my-server/display-simple-frame)

;; ----------------------------------------------------------------------
;; 3. Extra daemon safety (runs for every new client frame)
;; ----------------------------------------------------------------------
;; Already covered by the hook added in startup-config, but we make
;; absolutely sure here too (idempotent, harmless to call twice).
(when (daemonp)
  (add-hook 'server-after-make-frame-hook #'my-visual/apply-all-customisations t))



;; ----------------------------------------------------------------------
;; 4. Cleaning buffers when the last frame disappears
;; ----------------------------------------------------------------------
;; Make each new frame created from a daemon a new clean slate.  Only do this if
;; you really want a clean-slate from the daemon.  Most people leave this out;
;; the daemon is more useful when it remembers what you were working on.
(defun my-server/cleanup-on-last-frame (frame)
  "When FRAME is the last ordinary frame deleted, bury leftover buffers.
Buries buffers that are safe to drop on daemon cleanup."
  (when (and (daemonp)
             (= 1 (length (frame-list))))   ; only the (now-deleted) frame was left
    (dolist (buf (buffer-list))
      (with-current-buffer buf
        (unless (or (buffer-modified-p)
                    (get-buffer-process buf)
                    (string-match-p "\\` \\|\\*\\(Messages\\|scratch\\|Warnings\\|Completions\\)" (buffer-name)))
          (bury-buffer)   ; or (kill-buffer) if you are more aggressive
          )))))

(add-hook 'after-delete-frame-functions #'my-server/cleanup-on-last-frame)


(log/debug :fn 'server-support
           :msg "Ending load of the server-support module."
           :obj t)

(provide 'server-support)
;;; server-support.el ends here

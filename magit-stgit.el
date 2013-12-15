;;; magit-stgit.el --- StGit plug-in for Magit

;; Copyright (C) 2011-2013  The Magit Project Developers.
;;
;; For a full list of contributors, see the AUTHORS.md file
;; at the top-level directory of this distribution and at
;; https://raw.github.com/magit/magit/master/AUTHORS.md

;; Author: Lluís Vilanova <vilanova@ac.upc.edu>
;; Keywords: vc tools
;; Package: magit-stgit
;; Package-Requires: ((cl-lib "0.3") (magit "1.3.0"))

;; Magit is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; Magit is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with Magit.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; This plug-in provides StGit functionality as a separate component of Magit.

;; Available actions:
;; - visit: Shows the patch at point in the series (stg show)
;; - apply: Goes to the patch at point in the series (stg goto)
;; - discard: Deletes the marked/at point patch in the series (stg delete)

;; Available commands:
;; - `magit-stgit-refresh': Refresh the marked/at point patch in the series
;;   (stg refresh)
;; - `magit-stgit-repair': Repair the StGit metadata (stg repair)
;; - `magit-stgit-rebase': Rebase the whole series (stg rebase)

;; TODO:
;; - Let the user select which files must be included in a refresh.

;;; Code:

(require 'magit)
(eval-when-compile (require 'cl-lib))

;;; Options

(defcustom magit-stgit-executable "stg"
  "The name of the StGit executable."
  :group 'magit
  :type 'string)

(defface magit-stgit-patch
  '((t :inherit magit-log-sha1))
  "Face for name of a stgit patch."
  :group 'magit-faces)

(defface magit-stgit-current
  '((t :inherit magit-log-sha1))
  "Face for the current stgit patch."
  :group 'magit-faces)

(defface magit-stgit-marked
  '((t :inherit magit-stgit-current))
  "Face for a marked stgit patch."
  :group 'magit-faces)

(defface magit-stgit-applied
  '((t :inherit magit-cherry-equivalent))
  "Face for an applied stgit patch."
  :group 'magit-faces)

(defface magit-stgit-unapplied
  '((t :inherit magit-cherry-unmatched))
  "Face for an unapplied stgit patch."
  :group 'magit-faces)

(defface magit-stgit-empty
  '((t :inherit magit-diff-del))
  "Face for an empty stgit patch."
  :group 'magit-faces)

(defface magit-stgit-hidden
  '((t :inherit magit-diff-empty))
  "Face for an hidden stgit patch."
  :group 'magit-faces)

;;; Variables

(defvar-local magit-stgit-marked-patch nil
  "The (per-buffer) currently marked patch in an StGit series.")

(defvar magit-stgit-patch-buffer-name "*magit-stgit-patch*"
  "Name of buffer used to display a stgit patch.")

(defvar magit-stgit-patch-history nil
  "Input history for `magit-stgit-read-patch'.")

;;; Utilities

(defun magit-run-stgit (&rest args)
  (magit-with-refresh
    (magit-run* (cons magit-stgit-executable args))))

(defun magit-stgit-lines (&rest args)
  (with-temp-buffer
    (apply 'process-file magit-stgit-executable nil (list t nil) nil args)
    (split-string (buffer-string) "\n" 'omit-nulls)))

(defun magit-stgit-read-patch (prompt)
  (magit-completing-read prompt (magit-stgit-lines "series" "--noprefix")
                         nil nil nil 'magit-read-rev-history
                         magit-stgit-marked-patch))

;;; Commands

;;;###autoload
(defun magit-stgit-refresh (&optional patch)
  "Refresh a StGit patch."
  (interactive (list (magit-stgit-read-patch "Refresh patch")))
  (if patch
      (magit-run-stgit "refresh" "-p" patch)
    (magit-run-stgit "refresh")))

;;;###autoload
(defun magit-stgit-repair ()
  "Repair StGit metadata if branch was modified with git commands.
In the case of Git commits these will be imported as new patches
into the series."
  (interactive)
  (message "Repairing series...")
  (magit-run-stgit "repair")
  (message "Repairing series...done"))

;;;###autoload
(defun magit-stgit-rebase ()
  "Rebase an StGit patch series."
  (interactive)
  (when (magit-get-current-remote)
    (when (yes-or-no-p "Update remotes? ")
      (message "Updating remotes...")
      (magit-run-git-async "remote" "update")
      (message "Updating remotes...done"))
    (magit-run-stgit "rebase"
                     (format "remotes/%s/%s"
                             (magit-get-current-remote)
                             (magit-get-current-branch)))))

;;;###autoload
(defun magit-stgit-discard (patch)
  "Discard a StGit patch."
  (interactive (list (magit-stgit-read-patch "Discard patch")))
  (when (string= patch magit-stgit-marked-patch)
    (setq magit-stgit-marked-patch nil))
  (magit-run-stgit "delete" patch))

;;;###autoload
(defun magit-stgit-mark-patch (patch)
  "Mark a StGit patch."
  (interactive (list (magit-stgit-read-patch "Mark patch")))
  (setq magit-stgit-marked-patch
        (unless (string= magit-stgit-marked-patch patch)
          patch))
  (magit-refresh))

;;;###autoload
(defun magit-stgit-show-patch (patch)
  (interactive (list (magit-stgit-read-patch "Patch name")))
  (let ((dir default-directory)
        (buf (get-buffer-create magit-stgit-patch-buffer-name)))
    (with-current-buffer buf
      (magit-mode-display-buffer buf)
      (magit-mode-init dir
                       #'magit-commit-mode
                       #'magit-stgit-refresh-patch-buffer
                       patch))))

(defun magit-stgit-refresh-patch-buffer (patch)
  (magit-cmd-insert-section (stgit-patch)
      #'magit-wash-commit
    magit-stgit-executable "show" patch))

;;; Mode

(defvar magit-stgit-mode-lighter " Stg")

;;;###autoload
(define-minor-mode magit-stgit-mode
  "StGit support for Magit"
  :lighter magit-stgit-mode-lighter
  :require 'magit-stgit
  (or (derived-mode-p 'magit-mode)
      (error "This mode only makes sense with magit"))
  (if magit-stgit-mode
      (magit-add-section-hook 'magit-status-sections-hook
                              'magit-insert-stgit-series
                              'magit-insert-stashes t t)
    (remove-hook 'magit-status-sections-hook 'magit-insert-stgit-series t))
  (when (called-interactively-p 'any)
    (magit-refresh)))

;;;###autoload
(defun turn-on-magit-stgit ()
  "Unconditionally turn on `magit-stgit-mode'."
  (magit-stgit-mode 1))

(magit-add-action-clauses (item info "visit")
  ((stgit-patch)
   (magit-stgit-show-patch info)))

(magit-add-action-clauses (item info "apply")
  ((stgit-patch)
   (magit-run-stgit "goto" info)))

(magit-add-action-clauses (item info "discard")
  ((stgit-patch)
   (when (yes-or-no-p (format "Discard patch `%s'? " info))
     (magit-stgit-discard info))))

(magit-add-action-clauses (item info "mark")
  ((stgit-patch)
   (magit-stgit-mark-patch info)))

(easy-menu-define magit-stgit-extension-menu nil
  "StGit extension menu"
  '("StGit" :visible magit-stgit-mode
    ["Refresh patch" magit-stgit-refresh
     :help "Refresh the contents of a patch in an StGit series"]
    ["Repair" magit-stgit-repair
     :help "Repair StGit metadata if branch was modified with git commands"]
    ["Rebase series" magit-stgit-rebase
     :help "Rebase an StGit patch series"]))

(easy-menu-add-item 'magit-mode-menu '("Extensions")
                    magit-stgit-extension-menu)

;;; Series Section

(defconst magit-stgit-patch-re
  "^\\(.\\)\\([-+>!]\\) \\([^ ]+\\) +# \\(.+\\)$")

(defun magit-insert-stgit-series ()
  (when magit-stgit-mode
    (magit-cmd-insert-section (series "Patch series:")
        (apply-partially 'magit-wash-sequence 'magit-stgit-wash-patch)
      magit-stgit-executable "series" "--all" "--empty" "--description")))

(defun magit-stgit-wash-patch ()
  (looking-at magit-stgit-patch-re)
  (magit-bind-match-strings (empty state patch msg)
    (delete-region (point) (point-at-eol))
    (magit-with-section (section stgit-patch patch)
      (setf (magit-section-info section) patch)
      (insert (propertize state 'face
                          (cond ((equal state ">") 'magit-stgit-current)
                                ((equal state "+") 'magit-stgit-applied)
                                ((equal state "-") 'magit-stgit-unapplied)
                                ((equal state "!") 'magit-stgit-hidden)
                                (t (error "Unknown stgit patch state: %s"
                                          state))))
              (if (equal patch magit-stgit-marked-patch)
                  (propertize "<" 'face 'magit-stgit-marked)
                " ")
              (propertize empty 'face 'magit-stgit-empty) " "
              (propertize patch 'face 'magit-stgit-patch) " "
              (propertize msg   'face 'magit-stgit))
      (forward-line))))

(provide 'magit-stgit)
;; Local Variables:
;; indent-tabs-mode: nil
;; End:
;;; magit-stgit.el ends here

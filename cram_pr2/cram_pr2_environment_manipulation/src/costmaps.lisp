;;;
;;; Copyright (c) 2018, Christopher Pollok <cpollok@uni-bremen.de>
;;; All rights reserved.
;;;
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions are met:
;;;
;;;     * Redistributions of source code must retain the above copyright
;;;       notice, this list of conditions and the following disclaimer.
;;;     * Redistributions in binary form must reproduce the above copyright
;;;       notice, this list of conditions and the following disclaimer in the
;;;       documentation and/or other materials provided with the distribution.
;;;     * Neither the name of the Institute for Artificial Intelligence/
;;;       Universitaet Bremen nor the names of its contributors may be used to
;;;       endorse or promote products derived from this software without
;;;       specific prior written permission.
;;;
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
;;; AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
;;; IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
;;; ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
;;; LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
;;; CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
;;; SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
;;; INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
;;; CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
;;; ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
;;; POSSIBILITY OF SUCH DAMAGE.

(in-package :pr2-em)

(defun get-drawer-min-max-pose (container-desig)
  (let* ((handle-link
           (get-handle-link
            (desig:desig-prop-value container-desig :urdf-name)))
         (neutral-handle-pose
           (get-manipulated-pose
            (cl-urdf:name handle-link)
            0 :relative T))
         (manipulated-handle-pose
           (get-manipulated-pose
            (cl-urdf:name handle-link)
            1 :relative T)))
    (list neutral-handle-pose manipulated-handle-pose)))

(defun get-aabb (container-name)
  (btr:aabb
   (btr:rigid-body
    (btr:object btr:*current-bullet-world* :kitchen)
    (btr::make-rigid-body-name "KITCHEN" container-name))))

(defun get-width (container-name direction)
  "Return the width of the container with name `container-name',
appropriate for the joint `direction' given."
  (let ((dimensions (cl-bullet:bounding-box-dimensions (get-aabb container-name)))
        (norm-direction (cl-transforms:normalize-vector direction)))
    (if (> (abs (cl-transforms:x norm-direction))
           (abs (cl-transforms:y norm-direction)))
        (cl-transforms:y dimensions)
        (cl-transforms:x dimensions))))

;; NOTE(cpo): It might be useful to pass this the desired position
;; and calculate the current one to make the costmap more precise.
(defun make-opened-drawer-cost-function (?container-desig &optional (padding 0.2))
  "Resolve the relation according to the poses of the handle of `container-desig'
in neutral and manipulated form."
  (let* ((container-name
           (string-downcase
            (desig:desig-prop-value ?container-desig :urdf-name)))
         (handle-link
           (get-handle-link container-name))
         (handle-pose
           (get-manipulated-pose
            (cl-urdf:name handle-link)
            0 :relative T))
         (manipulated-handle-pose
           (get-manipulated-pose
            (cl-urdf:name handle-link)
            1 :relative T))
         (neutral-point
           (cl-transforms:make-3d-vector
            (cl-transforms:x (cl-transforms:origin handle-pose))
            (cl-transforms:y (cl-transforms:origin handle-pose))
            0))
         (manipulated-point
           (cl-transforms:make-3d-vector
            (cl-transforms:x (cl-transforms:origin manipulated-handle-pose))
            (cl-transforms:y (cl-transforms:origin manipulated-handle-pose))
            0))
         (V
           (cl-transforms:v- manipulated-point neutral-point))
         (width
           (get-width container-name V)))
    (lambda (x y)
      (multiple-value-bind (a b c)
          (line-equation-in-xy neutral-point manipulated-point)
        (let* ((P (cl-transforms:make-3d-vector x y 0))
               (dist (line-p-dist a b c P))
               (dist-p (line-p-dist-point a b c P)))
          (if (and
               (< dist (+ (/ width 2) padding))
               (< (cl-transforms:v-norm (cl-transforms:v- dist-p neutral-point))
                  (+ (cl-transforms:v-norm V) padding)))
              0
              1))))))

(defun make-opened-drawer-side-cost-function (?container-desig arm)
  (let* ((container-name
           (string-downcase
            (desig:desig-prop-value ?container-desig :urdf-name)))
         (handle-link
           (get-handle-link container-name))
         (handle-pose
           (get-manipulated-pose
            (cl-urdf:name handle-link)
            0 :relative T))
         (manipulated-handle-pose
           (get-manipulated-pose
            (cl-urdf:name handle-link)
            1 :relative T))
         (neutral-point
           (cl-transforms:make-3d-vector
            (cl-transforms:x (cl-transforms:origin handle-pose))
            (cl-transforms:y (cl-transforms:origin handle-pose))
            0))
         (manipulated-point
           (cl-transforms:make-3d-vector
            (cl-transforms:x (cl-transforms:origin manipulated-handle-pose))
            (cl-transforms:y (cl-transforms:origin manipulated-handle-pose))
            0))
         (AB
           (cl-transforms:v- manipulated-point neutral-point)))
    (lambda (x y)
      (let ((d (cl-transforms:z
                (cl-transforms:cross-product
                 AB
                 (cl-transforms:v- (cl-transforms:make-3d-vector x y 0)
                                   neutral-point)))))
        (if (and (< d 0) (eql arm :right))
            1.0
            (if (and (> d 0) (eql arm :left))
                1.0
                0.0))))))

(defmethod costmap:costmap-generator-name->score
    ((name (eql 'poses-reachable-cost-function))) 10)

(defmethod costmap:costmap-generator-name->score
    ((name (eql 'container-handle-reachable-cost-function))) 10)

(defmethod costmap:costmap-generator-name->score
    ((name (eql 'opened-drawer-cost-function))) 10)

(defmethod costmap:costmap-generator-name->score
    ((name (eql 'opened-drawer-side-cost-function))) 10)

(def-fact-group environment-manipulation-costmap (costmap:desig-costmap)
  (<- (costmap:desig-costmap ?designator ?costmap)
    (cram-robot-interfaces:reachability-designator ?designator)
    (spec:property ?designator (:object ?container-designator))
    (spec:property ?container-designator (:type ?container-type))
    (obj-int:object-type-subtype :container ?container-type)
    (spec:property ?container-designator (:urdf-name ?container-name))
    (spec:property ?designator (:arm ?arm))
    (costmap:costmap ?costmap)
    ;; reachability gaussian costmap
    (lisp-fun get-drawer-min-max-pose ?container-designator ?poses)
    (lisp-fun costmap:2d-pose-covariance ?poses 0.05 (?mean ?covariance))
    (costmap:costmap-add-function
     container-handle-reachable-cost-function
     (costmap:make-gauss-cost-function ?mean ?covariance)
     ?costmap)
    ;; cutting out drawer costmap
    (costmap:costmap-reach-minimal-distance ?padding)
    (costmap:costmap-add-function
     opened-drawer-cost-function
     (make-opened-drawer-cost-function ?container-designator ?padding)
     ?costmap)
    ;; cutting out for specific arm costmap
    (costmap:costmap-add-function
     opened-drawer-side-cost-function
     (make-opened-drawer-side-cost-function ?container-designator ?arm)
     ?costmap)
    ;; orientation generator
    (costmap:orientation-samples ?samples)
    (costmap:orientation-sample-step ?sample-step)
    (costmap:costmap-add-orientation-generator
     (costmap:make-angle-to-point-generator ?mean :samples ?samples :sample-step ?sample-step)
     ?costmap)))

# Purpose:
# Sets some properties (accessMode, annotations, labels) on new PV and PVCs attached to a
# given storageclass.
# This is needed by cephfs volumes to trigger certain behaviors on cephfs PVs and PVCs
# such as initializing volume, backup etc.
# If we need to set properties on PVs and PVCs using a storageclass, set
# these annotations on the storageclass:
# pvc.opa.openshift.ch/add-access-modes: <string-encoded yaml array of access modes to add to PVC>
# pv.opa.openshift.ch/set-default-annotations: <string-encoded yaml hash of annotations to set on PV (if annotation not already present)>
# pv.opa.openshift.ch/set-default-labels: <string-encoded yaml hash of labels to set on PV (if label not already present)>
package kubernetes.admission

import data.kubernetes.storageclasses

set_annotations_on_pv_key = "pv.opa.openshift.ch/set-default-annotations"
set_labels_on_pv_key = "pv.opa.openshift.ch/set-default-labels"
add_access_modes_on_pvc_key = "pvc.opa.openshift.ch/add-access-modes"


# when a storageClass defines a YAML-encoded hash in annotation <set_annotations_on_pv_key>
# of the form { <first_annotation_to_set_on_pv>: <value1>, <second_annotation_to_set_on_pv>: <value2> ... }
# add each annotation to any new PV using that storageclass if not present already
add_pv_annotations[annotation] = value {
    isNewPV
    storageclass := storageclasses[input.request.object.spec.storageClassName]
    pv_annotations_to_set = yaml.unmarshal(storageclass.metadata.annotations[set_annotations_on_pv_key])
    # the following line iterates over annotations that the storageClass wants to be set
    pv_annotations_to_set[annotation] = value
    # only set annotation if it's not already defined on input object
    not input.request.object.metadata.annotations[annotation]
}
# patch for annotations case1: object has not annotations
# we need to set the whole annotations hash in a single patch
patch[p] {
    not input.request.object.metadata["annotations"]
    count(add_pv_annotations) > 0
    p = { "op": "add", "path": "/metadata/annotations", "value": add_pv_annotations }
}
# patch for annotations case2: object already has annotations
# iterate over add_pv_annotations and generate a jsonpatch for each annotation to add
patch[p] {
    count(input.request.object.metadata["annotations"]) >= 0
    # the next line iterates on all annotations to add
    add_pv_annotations[annotation] = value
    json_path := concat("/", [ "/metadata/annotations", escapeForJsonPath(annotation) ])
    p = { "op": "add", "path": json_path, "value": value }
}

# when a storageClass defines a YAML-encoded hash in annotation <set_labels_on_pv_key>
# of the form { <first_label_to_set_on_pv>: <value1>, <second_label_to_set_on_pv>: <value2> ... }
# add each label to any new PV using that storageclass if not present already
add_pv_labels[label] = value {
    isNewPV
    storageclass := storageclasses[input.request.object.spec.storageClassName]
    pv_labels_to_set := yaml.unmarshal(storageclass.metadata.annotations[set_labels_on_pv_key])
    # the following line iterates over labels the storageclass wants to be set
    pv_labels_to_set[label] = value
    # only set label if it's not already defined on input object
    not input.request.object.metadata.labels[label]
}
# patch for labels case1: object has not labels
# we need to set the whole labels hash in a single patch
patch[p] {
    not input.request.object.metadata["labels"]
    count(add_pv_labels) > 0
    p = { "op": "add", "path": "/metadata/labels", "value": add_pv_labels }
}
# patch for labels case2: object already has labels
# iterate over add_pv_labels and generate a jsonpatch for each label to add
patch[p] {
    count(input.request.object.metadata["labels"]) >= 0
    # the next line iterates on all labels to add
    add_pv_labels[label] = value
    json_path := concat("/", [ "/metadata/labels", escapeForJsonPath(label) ])
    p = { "op": "add", "path": json_path, "value": value }
}

# when a storageClass defines a YAML-encoded array in annotation <add_access_modes_on_pvc_key>
# of the form [ "ReadWriteMany", "ReadWriteOnce", "ReadOnlyMany" ]
# add each accessMode to any new PVC using that storageclass if not present already
add_pvc_accessmodes[missing_mode] {
    isNewPVC
    storageclass := storageclasses[getPVCStorageClassName]
    access_modes := yaml.unmarshal(storageclass.metadata.annotations[add_access_modes_on_pvc_key])
    # iterate on the list of access_modes
    missing_mode := access_modes[_]
    # nothing to do if the access mode is already defined
    # This must be done with a separate rule due to the negation and the index
    # in the spec.accessModes array not being bound to a var (makes it is unsafe for rego)
    not input_pvc_has_access_mode(missing_mode)
}
# patch for accessModes case1: object has not accessmodes
# set the whole accessModes array in a single patch
patch[p] {
    not input.request.object.spec["accessModes"]
    count(add_pvc_accessmodes) > 0
    p = { "op": "add", "path": "/spec/accessModes", "value": add_pvc_accessmodes }
}
# patch for accessModes case2: object already has accessmodes
# iterate on add_pvc_accessmodes and generate a jsonpatch for each mode to add
patch[p] {
    count(input.request.object.spec["accessModes"]) >= 0
    add_pvc_accessmodes[_] = value
    p = { "op": "add", "path": "/spec/accessModes/-", "value": value }
}

# Helper rules/functions

input_pvc_has_access_mode(m) {
input.request.object.spec.accessModes[_] == m
}

isNewPV {
    input.request.kind.group == ""
    input.request.kind.kind == "PersistentVolume"
    input.request.operation == "CREATE"
}

isNewPVC {
    input.request.kind.group == ""
    input.request.kind.kind == "PersistentVolumeClaim"
    input.request.operation == "CREATE"
}

# case where the storage class name is specified in .spec.storageClassName
getPVCStorageClassName = storage_class_name {
    storage_class_name = input.request.object.spec.storageClassName
}

# case where the storage class name is specified in an annotation
# (this is deprecated but Openshift 3.11 console still does that)
getPVCStorageClassName = storage_class_name {
    # this only applies when there's no explicit .spec.storageClassName
    not input.request.object.spec.storageClassName
    storage_class_name = input.request.object.metadata.annotations["volume.beta.kubernetes.io/storage-class"]
}

# escape / as ~1 and ~ as ~0 http://tools.ietf.org/html/rfc6901#section-4
escapeForJsonPath(name) = escaped_name {
    intermediate := replace(name,"~","~0")
    escaped_name := replace(intermediate,"/","~1")
}

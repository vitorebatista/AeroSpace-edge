import Common

extension TreeNode {
    /// Returns the node's workspace override if set, otherwise the global config flag.
    /// A detached node belongs to no workspace, so it resolves to the global config.
    @MainActor func isNormalizationEnabled(_ kind: NormalizationKind) -> Bool {
        nodeWorkspace?.normalizationOverride[kind] ?? config.isNormalizationEnabledGlobally(kind)
    }
}

extension Config {
    fileprivate func isNormalizationEnabledGlobally(_ kind: NormalizationKind) -> Bool {
        switch kind {
            case .flattenContainers: enableNormalizationFlattenContainers
            case .oppositeOrientationForNestedContainers: enableNormalizationOppositeOrientationForNestedContainers
        }
    }
}

extension Workspace {
    @MainActor func normalizeContainers() {
        let root = rootTilingContainer
        // Always called: the function also removes effectively-empty containers and sets lifeStatus
        // regardless of the flatten flag. The flatten flag honours per-workspace overrides (fork: enable-normalization)
        root.unbindEmptyAndFlattenContainersRecursive(allowFlatten: isNormalizationEnabled(.flattenContainers))
        // rootTilingContainer.deriveAxLifeStatusRecursive()
        if config.enableNormalizationBinaryTree {
            rootTilingContainer.normalizeBinaryTree(rect: workspaceMonitorInfo.visibleRectPaddedByOuterGaps)
        } else if isNormalizationEnabled(.oppositeOrientationForNestedContainers) {
            rootTilingContainer.normalizeOppositeOrientationForNestedContainersRecursive(parentOrientation: nil)
        }
    }
}

extension TilingContainer {
    /// This function has probably way too many responsibilities:
    /// 1. It unbinds empty containers
    /// 2. It flattens containers that contain only a single child (excluding the root container)
    /// 3. It sets correct lifeStatus values
    ///
    /// todo: It's not clear what happens with mru in this function (does mru get rewritten by the recursive calls?).
    ///       Is it O(n^2) complexity?
    @MainActor fileprivate func unbindEmptyAndFlattenContainersRecursive(allowFlatten: Bool) {
        if isRootContainer { // Special logic for root node to keep it always bound
            if let child = children.singleOrNil() as? TilingContainer, allowFlatten {
                child.unbindFromParent()
                for grandChild in child.children {
                    let data = grandChild.unbindFromParent()
                    grandChild.bind(to: self, adaptiveWeight: data.adaptiveWeight, index: INDEX_BIND_LAST)
                }
                self.copyFrom(child)
            }
            for child in children {
                (child as? TilingContainer)?.unbindEmptyAndFlattenContainersRecursive(allowFlatten: allowFlatten)
            }
            self.lifeStatus = .alive
        } else if let child = children.singleOrNil(), allowFlatten {
            child.unbindFromParent()
            let mru = parent?.mostRecentChild
            let previousBinding = unbindFromParent() // Kill the current node
            child.bind(to: previousBinding.parent, adaptiveWeight: previousBinding.adaptiveWeight, index: previousBinding.index)
            (child as? TilingContainer)?.unbindEmptyAndFlattenContainersRecursive(allowFlatten: allowFlatten)
            if mru != self {
                mru?.markAsMostRecentChild()
            } else {
                child.markAsMostRecentChild()
            }
        } else {
            var inhabitedChildrenCount = 0
            for child in children {
                (child as? TilingContainer)?.unbindEmptyAndFlattenContainersRecursive(allowFlatten: allowFlatten)
                inhabitedChildrenCount += child.tilingTreeNodeCasesOrDie().isInhabited ? 1 : 0
            }
            if children.isEmpty {
                unbindFromParent()
            }
            if inhabitedChildrenCount == 1 && allowFlatten {
                lifeStatus = .mustBeFlattened
            } else {
                lifeStatus = inhabitedChildrenCount > 0 ? .alive : .deadOrInvisible
            }
        }
    }

    @MainActor func normalizeBinaryTree(rect: Rect) {
        forceBinaryTree()
        setOrientation(rect.width > rect.height ? .h : .v)
        switch children.count {
            case 0: return
            case 1:
                (children[0] as? TilingContainer)?.normalizeBinaryTree(rect: rect)
            default: // 2 — guaranteed by forceBinaryTree
                let rects = rect.sliced(along: orientation, weights: children.map { $0.getWeight(orientation) })
                (children[0] as? TilingContainer)?.normalizeBinaryTree(rect: rects[0])
                (children[1] as? TilingContainer)?.normalizeBinaryTree(rect: rects[1])
        }
    }

    @MainActor private func forceBinaryTree() {
        if children.count <= 2 { return }
        let toWrap = Array(children.dropFirst())
        let wrapper = TilingContainer.newHTiles(parent: self, adaptiveWeight: WEIGHT_AUTO, index: 1)
        for child in toWrap {
            child.unbindFromParent()
            child.bind(to: wrapper, adaptiveWeight: WEIGHT_AUTO, index: INDEX_BIND_LAST)
        }
    }
}

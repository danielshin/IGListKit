/**
 * Copyright (c) 2016-present, Facebook, Inc.
 * All rights reserved.
 *
 * This source code is licensed under the BSD-style license found in the
 * LICENSE file in the root directory of this source tree. An additional grant
 * of patent rights can be found in the PATENTS file in the same directory.
 */

#import "IGListStackedSectionControllerInternal.h"

#import <objc/runtime.h>

#import <IGListKit/IGListAssert.h>
#import <IGListKit/IGListSupplementaryViewSource.h>

#import "IGListSectionControllerInternal.h"

@interface UICollectionViewCell (IGListStackedSectionController)
@end
@implementation UICollectionViewCell (IGListStackedSectionController)

static void * kStackedSectionControllerKey = &kStackedSectionControllerKey;

- (void)ig_setStackedSectionController:(id)stackedSectionController {
    objc_setAssociatedObject(self, kStackedSectionControllerKey, stackedSectionController, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (id)ig_stackedSectionController {
    return objc_getAssociatedObject(self, kStackedSectionControllerKey);
}

static void * kStackedSectionControllerIndexKey = &kStackedSectionControllerIndexKey;

- (void)ig_setStackedSectionControllerIndex:(NSInteger)stackedSectionControllerIndex {
    objc_setAssociatedObject(self, kStackedSectionControllerIndexKey, @(stackedSectionControllerIndex), OBJC_ASSOCIATION_ASSIGN);
}

- (NSInteger)ig_stackedSectionControllerIndex {
    return [objc_getAssociatedObject(self, kStackedSectionControllerIndexKey) integerValue];
}

@end

@implementation IGListStackedSectionController

- (instancetype)initWithSectionControllers:(NSArray <IGListSectionController<IGListSectionType> *> *)sectionControllers {
    if (self = [super init]) {
        for (IGListSectionController<IGListSectionType> *sectionController in sectionControllers) {
            sectionController.collectionContext = self;
            sectionController.viewController = self.viewController;

            if (self.supplementaryViewSource == nil) {
                self.supplementaryViewSource = sectionController.supplementaryViewSource;
            }
        }

        _visibleSectionControllers = [[NSCountedSet alloc] init];
        _sectionControllers = [NSOrderedSet orderedSetWithArray:sectionControllers];

        self.displayDelegate = self;
        self.scrollDelegate = self;

        [self reloadData];
    }
    return self;
}


#pragma mark - Private API

- (void)reloadData {
    NSMutableArray *sectionControllers = [[NSMutableArray alloc] init];
    NSMutableArray *offsets = [[NSMutableArray alloc] init];

    NSUInteger numberOfItems = 0;
    for (IGListSectionController<IGListSectionType> *sectionController in self.sectionControllers) {
        [offsets addObject:@(numberOfItems)];

        const NSUInteger items = [sectionController numberOfItems];
        for (NSUInteger i = 0; i < items; i++) {
            [sectionControllers addObject:sectionController];
        }

        numberOfItems += items;
    }

    self.sectionControllerOffsets = offsets;
    self.flattenedNumberOfItems = numberOfItems;
    self.sectionControllersForItems = sectionControllers;

    IGAssert(self.sectionControllerOffsets.count == self.sectionControllers.count, @"Not enough offsets for section controllers");
    IGAssert(self.sectionControllersForItems.count == self.flattenedNumberOfItems, @"Controller map does not equal total number of items");
}

- (IGListSectionController <IGListSectionType> *)sectionControllerForObjectIndex:(NSUInteger)itemIndex {
    return self.sectionControllersForItems[itemIndex];
}

- (NSUInteger)offsetForSectionController:(IGListSectionController<IGListSectionType> *)sectionController {
    const NSUInteger index = [self.sectionControllers indexOfObject:sectionController];
    IGAssert(index != NSNotFound, @"Querying offset for an undocumented section controller");
    return [self.sectionControllerOffsets[index] integerValue];
}

- (NSUInteger)localIndexForSectionController:(IGListSectionController<IGListSectionType> *)sectionController index:(NSUInteger)index {
    const NSUInteger offset = [self offsetForSectionController:sectionController];
    IGAssert(offset <= index, @"Section controller offset must be less than or equal to the item index");
    return index - offset;
}

- (NSIndexSet *)itemIndexesForSectionController:(IGListSectionController<IGListSectionType> *)sectionController indexes:(NSIndexSet *)indexes {
    const NSUInteger offset = [self offsetForSectionController:sectionController];
    NSMutableIndexSet *itemIndexes = [[NSMutableIndexSet alloc] init];
    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        [itemIndexes addIndex:(idx + offset)];
    }];
    return itemIndexes;
}


#pragma mark - IGListSectionType

- (NSInteger)numberOfItems {
    return self.flattenedNumberOfItems;
}

- (CGSize)sizeForItemAtIndex:(NSInteger)index {
    IGListSectionController<IGListSectionType> *sectionController = [self sectionControllerForObjectIndex:index];
    const NSUInteger localIndex = [self localIndexForSectionController:sectionController index:index];
    return [sectionController sizeForItemAtIndex:localIndex];
}

- (UICollectionViewCell *)cellForItemAtIndex:(NSInteger)index {
    IGListSectionController<IGListSectionType> *sectionController = [self sectionControllerForObjectIndex:index];
    const NSUInteger localIndex = [self localIndexForSectionController:sectionController index:index];
    return [sectionController cellForItemAtIndex:localIndex];
}

- (void)didUpdateToObject:(id)object {
    for (IGListSectionController<IGListSectionType> *sectionController in self.sectionControllers) {
        [sectionController didUpdateToObject:object];
    }
}

- (void)didSelectItemAtIndex:(NSInteger)index {
    IGListSectionController<IGListSectionType> *sectionController = [self sectionControllerForObjectIndex:index];
    const NSUInteger localIndex = [self localIndexForSectionController:sectionController index:index];
    [sectionController didSelectItemAtIndex:localIndex];
}

#pragma mark - IGListCollectionContext

- (CGSize)containerSize {
    return [self.collectionContext containerSize];
}

- (NSUInteger)indexForCell:(UICollectionViewCell *)cell sectionController:(IGListSectionController<IGListSectionType> *)sectionController {
    const NSUInteger index = [self.collectionContext indexForCell:cell sectionController:self];
    return [self localIndexForSectionController:sectionController index:index];
}

- (UICollectionViewCell *)cellForItemAtIndex:(NSInteger)index sectionController:(IGListSectionController<IGListSectionType> *)sectionController {
    const NSUInteger offset = [self offsetForSectionController:sectionController];
    return [self.collectionContext cellForItemAtIndex:(index + offset) sectionController:self];
}

- (NSArray<UICollectionViewCell *> *)visibleCellsForSectionController:(IGListSectionController<IGListSectionType> *)sectionController {
    NSMutableArray *cells = [NSMutableArray new];
    id<IGListCollectionContext> collectionContext = self.collectionContext;
    NSArray *visibleCells = [collectionContext visibleCellsForSectionController:self];
    for (UICollectionViewCell *cell in visibleCells) {
        const NSUInteger index = [collectionContext indexForCell:cell sectionController:self];
        if (self.sectionControllersForItems[index] == sectionController) {
            [cells addObject:cell];
        }
    }
    return [cells copy];
}

- (void)deselectItemAtIndex:(NSInteger)index sectionController:(IGListSectionController<IGListSectionType> *)sectionController animated:(BOOL)animated {
    const NSUInteger localIndex = [self localIndexForSectionController:sectionController index:index];
    [self.collectionContext deselectItemAtIndex:localIndex sectionController:self animated:animated];
}

- (NSUInteger)sectionForSectionController:(IGListSectionController<IGListSectionType> *)sectionController {
    return [self.collectionContext sectionForSectionController:self];
}

- (UICollectionViewCell *)dequeueReusableCellOfClass:(Class)cellClass
                                forSectionController:(IGListSectionController<IGListSectionType> *)sectionController
                                             atIndex:(NSInteger)index {
    const NSUInteger offset = [self offsetForSectionController:sectionController];
    return (UICollectionViewCell *_Nonnull)[self.collectionContext dequeueReusableCellOfClass:cellClass
                                                                         forSectionController:self
                                                                                      atIndex:(index + offset)];
}

- (UICollectionViewCell *)dequeueReusableCellWithNibName:(NSString *)nibName
                                                  bundle:(NSBundle *)bundle
                                    forSectionController:(IGListSectionController<IGListSectionType> *)sectionController
                                                 atIndex:(NSInteger)index {
    const NSUInteger offset = [self offsetForSectionController:sectionController];
    return (UICollectionViewCell *_Nonnull)[self.collectionContext dequeueReusableCellWithNibName:nibName
                                                                                           bundle:bundle
                                                                             forSectionController:self
                                                                                          atIndex:(index + offset)];
}

- (UICollectionViewCell *)dequeueReusableCellFromStoryboardWithIdentifier:(NSString *)identifier
                                                     forSectionController:(IGListSectionController <IGListSectionType> *)sectionController
                                                                  atIndex:(NSInteger)index {
    const NSUInteger offset = [self offsetForSectionController:sectionController];
    return (UICollectionViewCell *_Nonnull)[self.collectionContext dequeueReusableCellFromStoryboardWithIdentifier:identifier
                                                                                              forSectionController:self
                                                                                                           atIndex:(index + offset)];
}

- (UICollectionReusableView *)dequeueReusableSupplementaryViewOfKind:(NSString *)elementKind
                                                forSectionController:(IGListSectionController<IGListSectionType> *)sectionController
                                                               class:(Class)viewClass
                                                             atIndex:(NSInteger)index {
    const NSUInteger offset = [self offsetForSectionController:sectionController];
    return (UICollectionViewCell *_Nonnull)[self.collectionContext dequeueReusableSupplementaryViewOfKind:elementKind
                                                                                     forSectionController:self
                                                                                                    class:viewClass
                                                                                                  atIndex:(index + offset)];
}

- (UICollectionReusableView *)dequeueReusableSupplementaryViewFromStoryboardOfKind:(NSString *)elementKind
                                                                    withIdentifier:(NSString *)identifier
                                                              forSectionController:(IGListSectionController<IGListSectionType> *)sectionController
                                                                           atIndex:(NSInteger)index {
    const NSUInteger offset = [self offsetForSectionController:sectionController];
    return (UICollectionViewCell *_Nonnull)[self.collectionContext dequeueReusableSupplementaryViewFromStoryboardOfKind:elementKind
                                                                                                         withIdentifier:identifier
                                                                                                   forSectionController:self
                                                                                                                atIndex:(index + offset)];
}

- (void)reloadInSectionController:(IGListSectionController<IGListSectionType> *)sectionController atIndexes:(NSIndexSet *)indexes {
    NSIndexSet *itemIndexes = [self itemIndexesForSectionController:sectionController indexes:indexes];
    [self.collectionContext reloadInSectionController:self atIndexes:itemIndexes];
}

- (void)insertInSectionController:(IGListSectionController<IGListSectionType> *)sectionController atIndexes:(NSIndexSet *)indexes {
    [self reloadData];
    NSIndexSet *itemIndexes = [self itemIndexesForSectionController:sectionController indexes:indexes];
    [self.collectionContext insertInSectionController:self atIndexes:itemIndexes];
}

- (void)deleteInSectionController:(IGListSectionController<IGListSectionType> *)sectionController atIndexes:(NSIndexSet *)indexes {
    [self reloadData];
    NSIndexSet *itemIndexes = [self itemIndexesForSectionController:sectionController indexes:indexes];
    [self.collectionContext deleteInSectionController:self atIndexes:itemIndexes];
}

- (void)reloadSectionController:(IGListSectionController<IGListSectionType> *)sectionController {
    [self reloadData];
    [self.collectionContext reloadSectionController:self];
}

- (void)performBatchAnimated:(BOOL)animated updates:(void (^)())updates completion:(void (^)(BOOL))completion {
    [self.collectionContext performBatchAnimated:animated updates:^{
        updates();
    } completion:^(BOOL finished) {
        [self reloadData];
        if (completion) {
            completion(finished);
        }
    }];
}


#pragma mark - IGListDisplayDelegate

- (void)listAdapter:(IGListAdapter *)listAdapter willDisplaySectionController:(IGListSectionController<IGListSectionType> *)sectionController cell:(UICollectionViewCell *)cell atIndex:(NSInteger)index {
    IGListSectionController<IGListSectionType> *childSectionController = [self sectionControllerForObjectIndex:index];
    const NSUInteger localIndex = [self localIndexForSectionController:childSectionController index:index];

    [cell ig_setStackedSectionController:childSectionController];
    [cell ig_setStackedSectionControllerIndex:localIndex];

    NSCountedSet *visibleSectionControllers = self.visibleSectionControllers;
    id<IGListDisplayDelegate> displayDelegate = [childSectionController displayDelegate];

    if ([visibleSectionControllers countForObject:childSectionController] == 0) {
        [displayDelegate listAdapter:listAdapter willDisplaySectionController:childSectionController];
    }
    [displayDelegate listAdapter:listAdapter willDisplaySectionController:childSectionController cell:cell atIndex:localIndex];

    [visibleSectionControllers addObject:childSectionController];
}

- (void)listAdapter:(IGListAdapter *)listAdapter didEndDisplayingSectionController:(IGListSectionController<IGListSectionType> *)sectionController cell:(UICollectionViewCell *)cell atIndex:(NSInteger)index {
    IGListSectionController<IGListSectionType> *childSectionController = [self sectionControllerForObjectIndex:index];
    const NSUInteger localIndex = [self localIndexForSectionController:childSectionController index:index];
    NSCountedSet *visibleSectionControllers = self.visibleSectionControllers;
    id<IGListDisplayDelegate> displayDelegate = [childSectionController displayDelegate];

    [displayDelegate listAdapter:listAdapter didEndDisplayingSectionController:childSectionController cell:cell atIndex:localIndex];

    [visibleSectionControllers removeObject:childSectionController];
    if ([visibleSectionControllers countForObject:childSectionController] == 0) {
        [displayDelegate listAdapter:listAdapter didEndDisplayingSectionController:childSectionController];
    }
}

- (void)listAdapter:(IGListAdapter *)listAdapter willDisplaySectionController:(IGListSectionController<IGListSectionType> *)sectionController {}
- (void)listAdapter:(IGListAdapter *)listAdapter didEndDisplayingSectionController:(IGListSectionController<IGListSectionType> *)sectionController {}

#pragma mark - IGListScrollDelegate

- (void)listAdapter:(IGListAdapter *)listAdapter didScrollSectionController:(IGListSectionController<IGListSectionType> *)sectionController {
    for (IGListSectionController<IGListSectionType> *childSectionController in self.sectionControllers) {
        [[childSectionController scrollDelegate] listAdapter:listAdapter didScrollSectionController:childSectionController];
    }
}

- (void)listAdapter:(IGListAdapter *)listAdapter willBeginDraggingSectionController:(IGListSectionController<IGListSectionType> *)sectionController {
    for (IGListSectionController<IGListSectionType> *childSectionController in self.sectionControllers) {
        [[childSectionController scrollDelegate] listAdapter:listAdapter willBeginDraggingSectionController:sectionController];
    }
}

- (void)listAdapter:(IGListAdapter *)listAdapter didEndDraggingSectionController:(IGListSectionController<IGListSectionType> *)sectionController willDecelerate:(BOOL)decelerate {
    for (IGListSectionController<IGListSectionType> *childSectionController in self.sectionControllers) {
        [[childSectionController scrollDelegate] listAdapter:listAdapter didEndDraggingSectionController:childSectionController willDecelerate:decelerate];
    }
}

@end

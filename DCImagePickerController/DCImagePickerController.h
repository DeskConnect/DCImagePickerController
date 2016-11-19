//
//  DCImagePickerController.h
//
//  Created by Conrad Kramer on 11/3/14.
//  Copyright (c) 2014 DeskConnect, LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DCImagePickerControllerSourceType) {
    DCImagePickerControllerSourceTypePhotoLibrary = UIImagePickerControllerSourceTypePhotoLibrary,
    DCImagePickerControllerSourceTypeSavedPhotosAlbum = UIImagePickerControllerSourceTypeSavedPhotosAlbum
};

@class DCImagePickerController;

@protocol DCImagePickerControllerDelegate <NSObject>
@optional
- (void)dcImagePickerController:(DCImagePickerController *)picker didFinishPickingMediaWithInfo:(NSArray *)info;
- (void)dcImagePickerControllerDidCancel:(DCImagePickerController *)picker;
@end

extern NSString * const DCImagePickerControllerAsset;

@interface DCImagePickerController : UINavigationController

+ (BOOL)isSourceTypeAvailable:(DCImagePickerControllerSourceType)sourceType;
+ (NSArray<NSString *> *)availableMediaTypesForSourceType:(DCImagePickerControllerSourceType)sourceType;

@property (nonatomic, weak) id <UINavigationControllerDelegate, DCImagePickerControllerDelegate> delegate;

@property (nonatomic) DCImagePickerControllerSourceType sourceType;
@property (nonatomic, copy) NSArray<NSString *> *mediaTypes;
@property (nonatomic) NSUInteger minimumNumberOfItems;
@property (nonatomic) NSUInteger maximumNumberOfItems;
@property (nonatomic) BOOL originalImageNotRequired; // Result media info dictionary will only include UIImagePickerControllerReferenceURL and DCImagePickerControllerAsset

@end

NS_ASSUME_NONNULL_END

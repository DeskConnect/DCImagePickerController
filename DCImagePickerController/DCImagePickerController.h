//
//  DCImagePickerController.h
//
//  Created by Conrad Kramer on 11/3/14.
//  Copyright (c) 2014 DeskConnect, LLC. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, DCImagePickerControllerSourceType) {
    DCImagePickerControllerSourceTypePhotoLibrary = UIImagePickerControllerSourceTypePhotoLibrary,
    DCImagePickerControllerSourceTypeSavedPhotosAlbum = UIImagePickerControllerSourceTypeSavedPhotosAlbum
};

@class DCImagePickerController;

@protocol DCImagePickerControllerDelegate <UINavigationControllerDelegate>
@optional
- (void)dcImagePickerController:(DCImagePickerController *)picker didFinishPickingMediaWithInfo:(NSArray *)info;
- (void)dcImagePickerControllerDidCancel:(DCImagePickerController *)picker;
@end

@interface DCImagePickerController : UINavigationController

+ (BOOL)isSourceTypeAvailable:(DCImagePickerControllerSourceType)sourceType;
+ (NSArray *)availableMediaTypesForSourceType:(DCImagePickerControllerSourceType)sourceType;

@property (nonatomic, weak) id <DCImagePickerControllerDelegate> delegate;

@property (nonatomic) DCImagePickerControllerSourceType sourceType;
@property (nonatomic, copy) NSArray *mediaTypes;
@property (nonatomic) NSUInteger minimumNumberOfItems;
@property (nonatomic) NSUInteger maximumNumberOfItems;
@property (nonatomic) BOOL originalImageNotRequired; // Result media info dictionary will only include UIImagePickerControllerReferenceURL

@end

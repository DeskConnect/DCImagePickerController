//
//  ViewController.m
//  Demo
//
//  Created by Conrad Kramer on 12/5/14.
//  Copyright (c) 2014 Conrad Kramer. All rights reserved.
//

#import "ViewController.h"
#import "DCImagePickerController.h"
#import <MobileCoreServices/MobileCoreServices.h>

@interface ViewController () <DCImagePickerControllerDelegate, UINavigationControllerDelegate, UIImagePickerControllerDelegate>

@end

@implementation ViewController

- (void)loadView {
    [super loadView];

    self.view.backgroundColor = [UIColor whiteColor];

    UIButton *customButton = [UIButton buttonWithType:UIButtonTypeSystem];
    customButton.translatesAutoresizingMaskIntoConstraints = NO;
    [customButton setTitle:@"DCImagePickerController" forState:UIControlStateNormal];
    [customButton addTarget:self action:@selector(showCustomImagePicker) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:customButton];

    UIButton *systemButton = [UIButton buttonWithType:UIButtonTypeSystem];
    systemButton.translatesAutoresizingMaskIntoConstraints = NO;
    [systemButton setTitle:@"UIImagePickerController" forState:UIControlStateNormal];
    [systemButton addTarget:self action:@selector(showSystemImagePicker) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:systemButton];

    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:customButton attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterX multiplier:1.0f constant:0.0f]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:customButton attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterY multiplier:1.0f constant:-40.0f]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:systemButton attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterX multiplier:1.0f constant:0.0f]];
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:systemButton attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeCenterY multiplier:1.0f constant:40.0f]];
}

- (void)showCustomImagePicker {
    DCImagePickerController *imagePickerController = [[DCImagePickerController alloc] init];
    imagePickerController.minimumNumberOfItems = 2;
    imagePickerController.maximumNumberOfItems = 5;
    imagePickerController.delegate = self;
    imagePickerController.mediaTypes = @[(id)kUTTypeImage, (id)kUTTypeMovie];
    imagePickerController.modalPresentationStyle = UIModalPresentationFormSheet;

    [self presentViewController:imagePickerController animated:YES completion:nil];
}

- (void)showSystemImagePicker {
    UIImagePickerController *imagePickerController = [[UIImagePickerController alloc] init];
    imagePickerController.delegate = self;
    imagePickerController.mediaTypes = @[(id)kUTTypeImage, (id)kUTTypeMovie];
    imagePickerController.modalPresentationStyle = UIModalPresentationFormSheet;

    [self presentViewController:imagePickerController animated:YES completion:nil];
}

#pragma mark - DCImagePickerControllerDelegate

- (void)dcImagePickerController:(DCImagePickerController *)picker didFinishPickingMediaWithInfo:(NSArray *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)dcImagePickerControllerDidCancel:(DCImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIImagePickerControllerDelegate

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

@end

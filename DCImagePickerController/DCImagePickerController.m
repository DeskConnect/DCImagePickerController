//
//  DCImagePickerController.m
//
//  Created by Conrad Kramer on 11/3/14.
//  Copyright (c) 2014 DeskConnect, LLC. All rights reserved.
//

#import <AssetsLibrary/AssetsLibrary.h>
#import <MobileCoreServices/MobileCoreServices.h>
#import <objc/runtime.h>

#import "DCImagePickerController.h"

@interface DCImagePickerController ()

@property (nonatomic, strong) ALAssetsLibrary *assetsLibrary;
@property (nonatomic, readonly, strong) ALAssetsFilter *assetsFilter;

- (void)finishedWithAssetURLs:(NSArray *)assetURLs;
- (void)cancel;

@end

#pragma mark - Utilities

static UIImage *DCAssetThumbnail(ALAsset *asset, CGSize size) {
    CGRect bounds = (CGRect){CGPointZero, size};
    UIGraphicsBeginImageContextWithOptions(bounds.size, YES, 0.0f);

    CGFloat scale = [[UIScreen mainScreen] scale];
    UIImage *thumbnail = [[UIImage alloc] initWithCGImage:asset.thumbnail scale:scale orientation:UIImageOrientationUp];
    [thumbnail drawInRect:bounds];

    CGFloat margin = 4.0f;

    if ([[asset valueForProperty:ALAssetPropertyType] isEqualToString:ALAssetTypeVideo]) {
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
        CGFloat components[] = {0.0f, 0.0f, 0.0f, 0.8f};
        CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, components, NULL, 2);
        CGPoint start = CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds) - 10 - margin * 2.0f);
        CGPoint end = CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds));
        CGContextDrawLinearGradient(UIGraphicsGetCurrentContext(), gradient, start, end, 0);
        CGColorSpaceRelease(colorSpace);
        CGGradientRelease(gradient);

        static CGPathRef videoPath = NULL;
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            CGMutablePathRef path = CGPathCreateMutable();
            CGPathAddRoundedRect(path, NULL, CGRectMake(0, 0, 9, 8), 2, 2);
            CGPathMoveToPoint(path, NULL, 10, 4);
            CGPathAddLineToPoint(path, NULL, 14, 0);
            CGPathAddLineToPoint(path, NULL, 14, 8);
            CGPathCloseSubpath(path);
            videoPath = CGPathCreateCopy(path);
            CGPathRelease(path);
        });

        UIBezierPath *path = [UIBezierPath bezierPathWithCGPath:videoPath];
        [path applyTransform:CGAffineTransformMakeTranslation(margin, CGRectGetMaxY(bounds) - 10 - margin)];
        [[UIColor whiteColor] setFill];
        [path fill];
    }

    NSNumber *duration = [asset valueForProperty:ALAssetPropertyDuration];
    if ([duration isKindOfClass:[NSNumber class]]) {
        NSDate *toDate = [NSDate date];
        NSDate *fromDate = [toDate dateByAddingTimeInterval:(-1.0f * [duration doubleValue])];
        NSCalendarUnit components = (NSCalendarUnit)(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitNanosecond);
        NSDateComponents *dateComponents = [[NSCalendar currentCalendar] components:components fromDate:fromDate toDate:toDate options:0];
        NSInteger second = dateComponents.second;
        if (dateComponents.nanosecond >= NSEC_PER_SEC / 2.0f)
            second += 1;
        NSString *durationString = [NSString stringWithFormat:@"%ld:%02ld", (long)dateComponents.minute, (long)second];
        if (dateComponents.hour)
            durationString = [NSString stringWithFormat:@"%ld:%@", (long)dateComponents.hour, durationString];

        UIFont *font = [UIFont systemFontOfSize:12.0f];
        if ([NSAttributedString instancesRespondToSelector:@selector(drawAtPoint:)]) {
            NSAttributedString *attributedDuration = [[NSAttributedString alloc] initWithString:durationString attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: [UIColor whiteColor]}];
            CGSize size = [attributedDuration size];
            [attributedDuration drawAtPoint:CGPointMake(CGRectGetMaxX(bounds) - size.width - margin, CGRectGetMaxY(bounds) - size.height - margin + 1)];
        } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
            CGSize size = [durationString sizeWithFont:font];
            [durationString drawAtPoint:CGPointMake(CGRectGetMaxX(bounds) - size.width - margin, CGRectGetMaxY(bounds) - size.height - margin + 2) withFont:font];
#pragma clang diagnostic pop
        }
    }

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    return image;
}

#pragma mark - DCAssetsTableViewCell

@class DCAssetsTableViewCell;

@protocol DCAssetsTableViewCellDelegate <NSObject>
@optional
- (void)cell:(DCAssetsTableViewCell *)cell didSelectImageViewAtIndex:(NSUInteger)index;
@end

@interface DCAssetsTableViewCell : UITableViewCell

@property (nonatomic, strong) NSArray *assets;
@property (nonatomic, weak) id<DCAssetsTableViewCellDelegate> delegate;

@end

@implementation DCAssetsTableViewCell {
    NSMutableArray *_imageViews;
    NSMutableArray *_selectedImageViews;
}

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        self.selectionStyle = UITableViewCellSelectionStyleNone;
        self.textLabel.hidden = YES;
        self.detailTextLabel.hidden = YES;
        self.imageView.hidden = YES;

        _imageViews = [NSMutableArray new];
        _selectedImageViews = [NSMutableArray new];
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    static UIImage *selectedImage = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CGRect bounds = CGRectMake(0, 0, 38.0f, 38.0f);
        UIGraphicsBeginImageContextWithOptions(bounds.size, NO, 0.0f);
        UIBezierPath *boundsPath = [UIBezierPath bezierPathWithRect:bounds];
        UIBezierPath *circlePath = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(bounds, 7, 7)];
        UIBezierPath *checkPath = [UIBezierPath bezierPath];
        [checkPath moveToPoint:CGPointMake(13, 19)];
        [checkPath addLineToPoint:CGPointMake(17, 23)];
        [checkPath addLineToPoint:CGPointMake(25, 16)];
        [[UIColor colorWithWhite:1.0f alpha:0.3f] setFill];
        [boundsPath fill];
        [[UIColor colorWithRed:0.071 green:0.337 blue:0.843 alpha:1.000] setFill];
        [circlePath fill];
        [[UIColor whiteColor] setStroke];
        [circlePath stroke];
        [checkPath stroke];
         selectedImage = [UIGraphicsGetImageFromCurrentImageContext() resizableImageWithCapInsets:UIEdgeInsetsMake(0, 0, 34, 34)];
        UIGraphicsEndImageContext();
    });

    CGFloat width = ((CGRectGetWidth(self.bounds) - _imageViews.count + 1) / _imageViews.count);
    [_imageViews enumerateObjectsUsingBlock:^(UIImageView *imageView, NSUInteger idx, BOOL *stop) {
        imageView.frame = CGRectMake((width + 1) * idx, 0, width, CGRectGetHeight(self.bounds) - 1);

        ALAsset *asset = [_assets objectAtIndex:idx];
        if (!asset || [asset isKindOfClass:[NSNull class]])
            return [imageView setImage:nil];

        imageView.image = DCAssetThumbnail(asset, imageView.frame.size);
    }];
    [_selectedImageViews enumerateObjectsUsingBlock:^(UIImageView *imageView, NSUInteger idx, BOOL *stop) {
        if ([imageView isKindOfClass:[NSNull class]])
            return;
        imageView.frame = CGRectMake((width + 1) * idx, 0, width, CGRectGetHeight(self.bounds) - 1);
        imageView.image = selectedImage;
    }];
}

- (void)setAssets:(NSArray *)assets {
    _assets = assets;

    while (_imageViews && _imageViews.count < assets.count) {
        UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(imageViewTapped:)];
        tapGestureRecognizer.delegate = self;

        UIImageView *imageView = [[UIImageView alloc] init];
        imageView.userInteractionEnabled = YES;
        imageView.contentMode = UIViewContentModeScaleAspectFill;
        imageView.clipsToBounds = YES;
        [imageView addGestureRecognizer:tapGestureRecognizer];
        [self addSubview:imageView];
        [_imageViews addObject:imageView];
    }
    while (_imageViews && _imageViews.count > assets.count) {
        UIImageView *imageView = [_imageViews lastObject];
        [imageView removeFromSuperview];
        [_imageViews removeObject:imageView];
    }

    for (UIImageView *selectedImageView in _selectedImageViews)
        if ([selectedImageView isKindOfClass:[UIView class]])
            [selectedImageView removeFromSuperview];
    [_selectedImageViews removeAllObjects];
    while (_selectedImageViews.count < assets.count)
        [_selectedImageViews addObject:[NSNull null]];

    [self setNeedsLayout];
}

- (void)setSelected:(BOOL)selected atIndex:(NSUInteger)index {
    UIImageView *imageView = [_selectedImageViews objectAtIndex:index];
    imageView = [imageView isKindOfClass:[NSNull class]] ? nil : imageView;
    if (selected) {
        if (!imageView) {
            imageView = [[UIImageView alloc] init];
            [self addSubview:imageView];
        }
        [_selectedImageViews replaceObjectAtIndex:index withObject:imageView];
        [self setNeedsLayout];
    } else {
        [imageView removeFromSuperview];
        [_selectedImageViews replaceObjectAtIndex:index withObject:[NSNull null]];
    }
}

- (void)imageViewTapped:(UIGestureRecognizer *)sender {
    NSUInteger idx = [_imageViews indexOfObject:sender.view];
    if (idx != NSNotFound && [self.delegate respondsToSelector:@selector(cell:didSelectImageViewAtIndex:)])
        [self.delegate cell:self didSelectImageViewAtIndex:idx];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    return YES;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch {
    return [gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]];
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRequireFailureOfGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([otherGestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]] && [gestureRecognizer isKindOfClass:[UITapGestureRecognizer class]])
        return YES;

    return NO;
}

@end

#pragma mark - ALAssetsGroup (DCImagePickerController)

@interface ALAssetsGroup (DCImagePickerController)

@property (nonatomic, copy, getter=_dc_customName, setter=_dc_setCustomName:) NSString *customName;
@property (nonatomic, copy, getter=_dc_customFilter, setter=_dc_setCustomFilter:) ALAssetsFilter *customFilter;

@end

static char customNameKey;
static char customFilterKey;

@implementation ALAssetsGroup (DCImagePickerController)

- (void)_dc_setCustomName:(NSString *)customName {
    objc_setAssociatedObject(self, &customNameKey, customName, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

- (NSString *)_dc_customName {
    return objc_getAssociatedObject(self, &customNameKey);
}

- (void)_dc_setCustomFilter:(ALAssetsFilter *)customFilter {
    [self setAssetsFilter:customFilter];
    objc_setAssociatedObject(self, &customFilterKey, customFilter, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (ALAssetsFilter *)_dc_customFilter {
    return objc_getAssociatedObject(self, &customFilterKey);
}

@end

#pragma mark - DCGroupViewController

@interface DCGroupViewController : UITableViewController <DCAssetsTableViewCellDelegate>

@property (nonatomic, readonly, strong) ALAssetsGroup *group;
@property (nonatomic) NSInteger itemsPerRow;
@property (nonatomic, weak) UILabel *countLabel;

@end

@implementation DCGroupViewController {
    NSInteger _itemsPerRow;
    NSMutableSet *_selectedAssets;
    NSInteger _numberOfPhotos;
    NSInteger _numberOfVideos;
    ALAssetsFilter *_assetsFilter;
    CGRect _lastFrame;
}

- (DCImagePickerController *)imagePickerController {
    return (DCImagePickerController *)self.navigationController;
}

- (instancetype)initWithGroup:(ALAssetsGroup *)group {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _group = group;
        _itemsPerRow = 4;
        _selectedAssets = [NSMutableSet new];
        self.title = (group.customName ?: [group valueForProperty:ALAssetsGroupPropertyName]);
        [self setAssetsFilter:[ALAssetsFilter allAssets]];

        UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
        item.style = UIBarButtonItemStyleDone;
        self.navigationItem.rightBarButtonItem = item;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UILabel *countLabel = [[UILabel alloc] init];
    countLabel.font = [UIFont systemFontOfSize:17.0f];
    _countLabel = countLabel;
    [self updateCountLabel];

    UIView *footerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 0, 68)];
    [footerView addSubview:countLabel];

    self.tableView.separatorColor = [UIColor clearColor];
    self.tableView.tableFooterView = footerView;
    [self.tableView reloadData];
}

- (void)setItemsPerRow:(NSInteger)itemsPerRow {
    if (!itemsPerRow)
        return;

    _itemsPerRow = itemsPerRow;
    [self.tableView reloadData];
}

- (void)setAssetsFilter:(ALAssetsFilter *)assetsFilter {
    [_group setAssetsFilter:[ALAssetsFilter allPhotos]];
    _numberOfPhotos = [_group numberOfAssets];
    [_group setAssetsFilter:[ALAssetsFilter allVideos]];
    _numberOfVideos = [_group numberOfAssets];
    [_group setAssetsFilter:assetsFilter];
    [self updateCountLabel];
    [self.tableView reloadData];
}

- (void)updateCountLabel {
    NSInteger numberOfAssets = [_group numberOfAssets];
    NSInteger numberOfVideos = (numberOfAssets - _numberOfPhotos);
    NSInteger numberOfPhotos = (numberOfAssets - _numberOfVideos);
    NSString *photos = nil, *videos = nil;;
    if (_numberOfVideos == numberOfVideos || numberOfVideos == 0)
        photos = [NSString stringWithFormat:@"%ld Photos", (long)_numberOfPhotos];
    if (_numberOfPhotos == numberOfPhotos || numberOfPhotos == 0)
        videos = [NSString stringWithFormat:@"%ld Videos", (long)_numberOfVideos];

    NSMutableArray *components = [NSMutableArray new];
    if (photos && (_numberOfPhotos || !videos || (!_numberOfPhotos && !_numberOfVideos)))
        [components addObject:photos];
    if (videos && (_numberOfVideos || !photos || (!_numberOfPhotos && !_numberOfVideos)))
        [components addObject:videos];
    _countLabel.text = [components componentsJoinedByString:@", "];
    [_countLabel sizeToFit];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect bounds = self.tableView.tableFooterView.bounds;
    self.countLabel.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));

    if (!CGRectEqualToRect(_lastFrame, self.tableView.frame)) {
        self.itemsPerRow = (NSInteger)floor(self.tableView.contentSize.width / 80.0f);
        if (self.tableView.contentSize.height > CGRectGetMaxY(self.tableView.bounds)) {
            // This is a workaround for a bug in iOS 7
            CGFloat footerHeight = (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_7_0 && kCFCoreFoundationVersionNumber < 1140.10 ? CGRectGetHeight(self.tableView.tableFooterView.bounds) : 0.0f);
            [self.tableView setContentOffset:CGPointMake(0, self.tableView.contentSize.height - CGRectGetHeight(self.tableView.bounds) + footerHeight) animated:NO];
        }
        _lastFrame = self.tableView.frame;
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    self.navigationItem.rightBarButtonItem.enabled = (_selectedAssets.count >= self.imagePickerController.minimumNumberOfItems);
    self.itemsPerRow = (NSInteger)floor(self.tableView.contentSize.width / 80.0f);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return (NSInteger)ceil((CGFloat)_group.numberOfAssets / _itemsPerRow);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const DCAssetsTableViewCellIdentifier = @"DCAssetsTableViewCellIdentifier";
    DCAssetsTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DCAssetsTableViewCellIdentifier];
    if (!cell)
        cell = [[DCAssetsTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:DCAssetsTableViewCellIdentifier];

    NSMutableArray *assets = [NSMutableArray new];
    NSRange range = NSMakeRange(indexPath.row * _itemsPerRow, MIN(_itemsPerRow, _group.numberOfAssets - indexPath.row * _itemsPerRow));
    [_group enumerateAssetsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:range] options:0 usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
        if (result)
            [assets addObject:result];
        else if (index < range.location + range.length)
            [assets addObject:[NSNull null]];
    }];
    while (assets && assets.count < _itemsPerRow)
        [assets addObject:[NSNull null]];

    cell.assets = assets;
    cell.delegate = self;

    [assets enumerateObjectsUsingBlock:^(ALAsset *asset, NSUInteger idx, BOOL *stop) {
        if ([asset isKindOfClass:[NSNull class]])
            asset = nil;

        NSURL *assetURL = nil;
        if ([ALAssetsLibrary respondsToSelector:@selector(authorizationStatus)]) {
            assetURL = [asset valueForProperty:ALAssetPropertyAssetURL];
        } else {
            assetURL = [[[asset valueForProperty:ALAssetPropertyURLs] allValues] firstObject];
        }

        [cell setSelected:[_selectedAssets containsObject:assetURL] atIndex:idx];
    }];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return floor((CGRectGetWidth(self.tableView.bounds) - _itemsPerRow + 1) / _itemsPerRow);
}

- (void)done {
    [self.imagePickerController finishedWithAssetURLs:_selectedAssets.allObjects];
}

- (void)cell:(DCAssetsTableViewCell *)cell didSelectImageViewAtIndex:(NSUInteger)index {
    index += [self.tableView indexPathForCell:cell].row * _itemsPerRow;
    if (index < _group.numberOfAssets) {
        __block ALAsset *asset = nil;
        [_group enumerateAssetsAtIndexes:[NSIndexSet indexSetWithIndex:index] options:0 usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
            if (result)
                asset = result;
        }];
        
        DCImagePickerController *imagePickerController = self.imagePickerController;
        NSUInteger maximumNumberOfItems = imagePickerController.maximumNumberOfItems;
        NSUInteger minimumNumberOfItems = imagePickerController.minimumNumberOfItems;
        NSURL *assetURL = nil;
        if ([ALAssetsLibrary respondsToSelector:@selector(authorizationStatus)]) {
            assetURL = [asset valueForProperty:ALAssetPropertyAssetURL];
        } else {
            assetURL = [[[asset valueForProperty:ALAssetPropertyURLs] allValues] firstObject];
        }
        if ([_selectedAssets containsObject:assetURL])
            [_selectedAssets removeObject:assetURL];
        else if (_selectedAssets.count < maximumNumberOfItems || !maximumNumberOfItems)
            [_selectedAssets addObject:assetURL];

        [cell setSelected:([_selectedAssets containsObject:assetURL]) atIndex:(index % _itemsPerRow)];
        self.navigationItem.rightBarButtonItem.enabled = (_selectedAssets.count >= minimumNumberOfItems);
    }
}

@end

#pragma mark - DCGroupTableViewCell

@interface DCGroupTableViewCell : UITableViewCell

@property (nonatomic, weak) ALAssetsGroup *group;

@end

@implementation DCGroupTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (self) {
        self.textLabel.font = [UIFont systemFontOfSize:17.0f];
        self.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect frame = self.detailTextLabel.frame;
    frame.origin.y += 5;
    self.detailTextLabel.frame = frame;
}

- (void)setGroup:(ALAssetsGroup *)group {
    _group = group;
    self.textLabel.text = (group.customName ?: [group valueForProperty:ALAssetsGroupPropertyName]);
    self.detailTextLabel.text = [@(group.numberOfAssets) stringValue];
    self.imageView.contentMode = UIViewContentModeCenter;

    static NSCache *thumbnailCache = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        thumbnailCache = [[NSCache alloc] init];
    });

    UIImage *thumbnail = [thumbnailCache objectForKey:group];
    self.imageView.image = thumbnail;
    [self setNeedsLayout];

    if (thumbnail)
        return;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        CGFloat width = 68.0f;
        CGFloat height = width + 6.0f;
        CGFloat scale = [[UIScreen mainScreen] scale];
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, width * scale, height * scale, 8, sizeof(UInt32) * width * scale, colorSpace, kCGBitmapByteOrder32Big |kCGImageAlphaPremultipliedLast);
        CGContextTranslateCTM(context, 0.0f, height * scale);
        CGContextScaleCTM(context, scale, -scale);
        __block NSUInteger drawn = 0;
        [group enumerateAssetsWithOptions:NSEnumerationReverse usingBlock:^(ALAsset *result, NSUInteger index, BOOL *stop) {
            CGImageRef image = result.thumbnail;
            if (!image) {
                if (index)
                    return;
                else
                    image = group.posterImage;
            }
            CGContextSaveGState(context);
            CGSize imageSize = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
            CGRect clipRect = CGRectMake(drawn * 2.0f, (2 - drawn) * 3.0f, width - drawn * 4.0f, drawn == 0 ? width : 2.0f);
            CGContextClipToRect(context, clipRect);
            CGRect drawRect = clipRect;
            drawRect.size.height = width;
            CGFloat scaleX = CGRectGetWidth(drawRect) / imageSize.width;
            CGFloat scaleY = CGRectGetHeight(drawRect) / imageSize.height;
            CGFloat imageScale = (fabs(scaleX - 1.0f) < fabs(scaleY - 1.0f) ? scaleX : scaleY);
            drawRect = CGRectMake(clipRect.origin.x - (((imageScale * imageSize.width) - CGRectGetWidth(drawRect)) / 2.0f), clipRect.origin.y - (((imageScale * imageSize.height) - CGRectGetHeight(drawRect)) / 2.0f), imageScale * imageSize.width, imageScale * imageSize.height);
            CGAffineTransform transform = CGAffineTransformConcat(CGAffineTransformMakeScale(1.0f, -1.0f), CGAffineTransformMakeTranslation(0, -height));
            CGContextConcatCTM(context, transform);
            drawRect = CGRectApplyAffineTransform(drawRect, transform);
            CGContextDrawImage(context, drawRect, image);
            CGContextRestoreGState(context);
            drawn++;
            *stop = (drawn > 2);
        }];

        CGImageRef image = CGBitmapContextCreateImage(context);
        [thumbnailCache setObject:[UIImage imageWithCGImage:image scale:scale orientation:UIImageOrientationUp] forKey:group];
        CGImageRelease(image);
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);

        dispatch_async(dispatch_get_main_queue(), ^{
            self.imageView.image = [thumbnailCache objectForKey:self.group];
            [self setNeedsLayout];
        });
    });

}

@end

#pragma mark - DCGroupsTableViewController

@interface DCGroupsTableViewController : UITableViewController

@property (nonatomic, readonly) DCImagePickerController *imagePickerController;
@property (nonatomic, strong) NSArray *groups;

@end

@implementation DCGroupsTableViewController

- (DCImagePickerController *)imagePickerController {
    return (DCImagePickerController *)self.navigationController;
}

- (instancetype)init {
    self = [super init];
    if (!self)
        return nil;
    
    self.title = @"Photos";
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self.imagePickerController action:@selector(cancel)];

    self.tableView.rowHeight = 86.0f;
    self.tableView.separatorColor = [UIColor clearColor];

    void (^failure)(NSError *) = ^(NSError *error) {
        NSLog(@"%@: Error enumerating groups", self.imagePickerController);
        [self.imagePickerController cancel];
    };

    ALAssetsLibrary *assetsLibrary = self.imagePickerController.assetsLibrary;
    NSMutableArray *groups = [NSMutableArray new];
    [assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
        if (group) {
            [groups addObject:group];
        } else {
            [assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupAll usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
                if ([[group valueForProperty:ALAssetsGroupPropertyType] isEqualToNumber:@(ALAssetsGroupSavedPhotos)]) {
                    if ([self.imagePickerController.mediaTypes containsObject:(id)kUTTypeMovie]) {
                        group.customName = @"Videos";
                        group.customFilter = [ALAssetsFilter allVideos];
                        [groups addObject:group];
                    }
                    *stop = YES;
                } else {
                    NSArray *sorting = @[@(ALAssetsGroupSavedPhotos), @(ALAssetsGroupPhotoStream), @(ALAssetsGroupEvent), @(ALAssetsGroupAlbum), @(ALAssetsGroupFaces)];
                    self.groups = [groups sortedArrayWithOptions:0 usingComparator:^NSComparisonResult(ALAssetsGroup *obj1, ALAssetsGroup *obj2) {
                        ALAssetsGroupType type1 = [[obj1 valueForProperty:ALAssetsGroupPropertyType] unsignedIntegerValue];
                        ALAssetsGroupType type2 = [[obj2 valueForProperty:ALAssetsGroupPropertyType] unsignedIntegerValue];
                        NSComparisonResult result = [@([sorting indexOfObject:@(type1)]) compare:@([sorting indexOfObject:@(type2)])];
                        if (result == NSOrderedSame)
                            result = (obj1.customName ? (obj2.customName ? NSOrderedSame : NSOrderedDescending) : (obj2.customName ? NSOrderedAscending : NSOrderedSame));
                        return result;
                    }];
                    [self.tableView reloadData];
                }
            } failureBlock:failure];
        }
    } failureBlock:failure];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.groups.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString * const DCGroupTableViewCellIdentifier = @"DCGroupTableViewCellIdentifier";
    DCGroupTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DCGroupTableViewCellIdentifier];
    if (!cell) {
        cell = [[DCGroupTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:DCGroupTableViewCellIdentifier];
    }

    cell.group = [self.groups objectAtIndex:indexPath.row];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    ALAssetsGroup *group = [self.groups objectAtIndex:indexPath.row];
    DCGroupViewController *groupViewController = [[DCGroupViewController alloc] initWithGroup:group];
    [groupViewController setAssetsFilter:(group.customFilter ?: self.imagePickerController.assetsFilter)];
    [self.navigationController pushViewController:groupViewController animated:YES];
}

@end

#pragma mark - DCImagePickerController

@implementation DCImagePickerController {
    ALAssetsFilter *_assetsFilter;
}

@dynamic delegate;

+ (BOOL)isSourceTypeAvailable:(DCImagePickerControllerSourceType)sourceType {
    if (sourceType == DCImagePickerControllerSourceTypePhotoLibrary || sourceType == DCImagePickerControllerSourceTypeSavedPhotosAlbum) {
        ALAuthorizationStatus status = [ALAssetsLibrary authorizationStatus];
        return (status == ALAuthorizationStatusNotDetermined || status == ALAuthorizationStatusAuthorized);
    } 

    return NO;
}

+ (NSArray *)availableMediaTypesForSourceType:(DCImagePickerControllerSourceType)sourceType {
    return @[(id)kUTTypeImage, (id)kUTTypeMovie];
}

- (instancetype)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.assetsLibrary = [[ALAssetsLibrary alloc] init];
        self.sourceType = DCImagePickerControllerSourceTypePhotoLibrary;
        self.mediaTypes = [[self class] availableMediaTypesForSourceType:self.sourceType];
    }
    return self;
}

- (void)setSourceType:(DCImagePickerControllerSourceType)sourceType {
    if (sourceType == DCImagePickerControllerSourceTypePhotoLibrary) {
        DCGroupsTableViewController *albumsViewController = [[DCGroupsTableViewController alloc] init];
        [self setViewControllers:@[albumsViewController] animated:NO];
        _sourceType = sourceType;
    } else if (sourceType == DCImagePickerControllerSourceTypeSavedPhotosAlbum) {
        [self.assetsLibrary enumerateGroupsWithTypes:ALAssetsGroupSavedPhotos usingBlock:^(ALAssetsGroup *group, BOOL *stop) {
            *stop = (group != nil);
            if (group) {
                DCGroupViewController *groupViewController = [[DCGroupViewController alloc] initWithGroup:group];
                [groupViewController setAssetsFilter:(group.customFilter ?: _assetsFilter)];
                [self setViewControllers:@[groupViewController] animated:NO];
                _sourceType = sourceType;
            }
        } failureBlock:^(NSError *error) {
            NSLog(@"%@: Error enumerating saved photos", self);
            [self cancel];
        }];
    }
}

- (void)setMediaTypes:(NSArray *)mediaTypes {
    _mediaTypes = mediaTypes;

    if ([mediaTypes containsObject:(id)kUTTypeImage] && [mediaTypes containsObject:(id)kUTTypeMovie])
        _assetsFilter = [ALAssetsFilter allAssets];
    else if ([mediaTypes containsObject:(id)kUTTypeImage])
        _assetsFilter = [ALAssetsFilter allPhotos];
    else if ([mediaTypes containsObject:(id)kUTTypeMovie])
        _assetsFilter = [ALAssetsFilter allVideos];

    DCGroupViewController *groupViewController = ([self.topViewController isKindOfClass:[DCGroupViewController class]] ? (DCGroupViewController *)self.topViewController : nil);
    [groupViewController setAssetsFilter:(groupViewController.group.customFilter ?: _assetsFilter)];
}

- (void)setMinimumNumberOfItems:(NSUInteger)minimumNumberOfItems {
    NSParameterAssert(minimumNumberOfItems <= _maximumNumberOfItems || _maximumNumberOfItems == 0);
    _minimumNumberOfItems = minimumNumberOfItems;
}

- (void)setMaximumNumberOfItems:(NSUInteger)maximumNumberOfItems {
    NSParameterAssert(maximumNumberOfItems >= _minimumNumberOfItems || maximumNumberOfItems == 0);
    _maximumNumberOfItems = maximumNumberOfItems;
}

- (void)finishedWithAssetURLs:(NSArray *)assetURLs {
    if ([self.delegate respondsToSelector:@selector(dcImagePickerController:didFinishPickingMediaWithInfo:)]) {
        NSMutableArray *infos = [NSMutableArray new];
        NSMutableArray *assets = [NSMutableArray new];
        dispatch_group_t group = dispatch_group_create();
        for (NSURL *assetURL in assetURLs) {
            dispatch_group_enter(group);
            NSMutableDictionary *assetInfo = [NSMutableDictionary new];
            [assetInfo setObject:assetURL forKey:UIImagePickerControllerReferenceURL];
            [self.assetsLibrary assetForURL:assetURL resultBlock:^(ALAsset *asset) {
                [assetInfo setValue:[asset valueForProperty:ALAssetPropertyType] forKey:UIImagePickerControllerMediaType];
                if (!self.originalImageNotRequired)
                    [assetInfo setValue:[UIImage imageWithCGImage:asset.defaultRepresentation.fullResolutionImage] forKey:UIImagePickerControllerOriginalImage];
                [infos addObject:assetInfo];
                [assets addObject:(asset ?: [NSNull null])];
                dispatch_group_leave(group);
            } failureBlock:^(NSError *error) {
                [infos addObject:assetInfo];
                [assets addObject:[NSNull null]];
                dispatch_group_leave(group);
            }];
        }
        dispatch_group_notify(group, dispatch_get_main_queue(), ^{
            [infos sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
                ALAsset *asset1 = [assets objectAtIndex:[infos indexOfObject:obj1]];
                ALAsset *asset2 = [assets objectAtIndex:[infos indexOfObject:obj2]];
                NSDate *date1 = (([asset1 isKindOfClass:[NSNull class]] ? nil : [asset1 valueForProperty:ALAssetPropertyDate]) ?: [NSDate distantPast]);
                NSDate *date2 = (([asset2 isKindOfClass:[NSNull class]] ? nil : [asset2 valueForProperty:ALAssetPropertyDate]) ?: [NSDate distantPast]);
                return [date1 compare:date2];
            }];
            [self.delegate dcImagePickerController:self didFinishPickingMediaWithInfo:infos];
        });
    }
}

- (void)cancel {
    if ([self.delegate respondsToSelector:@selector(dcImagePickerControllerDidCancel:)])
        [self.delegate dcImagePickerControllerDidCancel:self];
}

@end

//
//  DCImagePickerController.m
//
//  Created by Conrad Kramer on 11/3/14.
//  Copyright (c) 2014 DeskConnect, LLC. All rights reserved.
//

#import <AssetsLibrary/AssetsLibrary.h>
#import <Photos/Photos.h>
#import <MobileCoreServices/MobileCoreServices.h>

#import "DCImagePickerController.h"

NS_ASSUME_NONNULL_BEGIN

@interface DCImagePickerController ()

@property (nonatomic, readonly) BOOL cancelled;

- (void)finishedWithAssets:(NSArray<PHAsset *> *)assets;
- (void)cancel;

@end

#pragma mark - Utilities

static NSPredicate *DCMediaTypePredicateFromMediaTypes(NSArray<NSString *> *mediaTypes) {
    NSMutableArray<NSPredicate *> *subpredicates = [NSMutableArray new];
    for (NSString *mediaType in mediaTypes) {
        if ([mediaType isEqualToString:(id)kUTTypeImage])
            [subpredicates addObject:[NSPredicate predicateWithFormat:@"mediaType = %ld", (long)PHAssetMediaTypeImage]];
        if ([mediaType isEqualToString:(id)kUTTypeMovie])
            [subpredicates addObject:[NSPredicate predicateWithFormat:@"mediaType = %ld", (long)PHAssetMediaTypeVideo]];
    }
    return [NSCompoundPredicate orPredicateWithSubpredicates:subpredicates];
}

static NSString * __nullable DCMediaTypeFromPHAsset(PHAsset *asset) {
    switch (asset.mediaType) {
        case PHAssetMediaTypeImage:
            return (__bridge id)kUTTypeImage;
        case PHAssetMediaTypeVideo:
            return (__bridge id)kUTTypeMovie;
        default:
            return nil;
    }
}

static NSURL * __nullable DCALAssetURLFromPHAsset(PHAsset *asset) {
    NSString *identifier = [[asset.localIdentifier componentsSeparatedByString:@"/"] firstObject];
    if (identifier.length != 36)
        return nil;
    
    return [NSURL URLWithString:[NSString stringWithFormat:@"assets-library://asset/asset.JPG?id=%@", identifier]];
}

static void DCOverylayDetailsOnPHAssetImage(PHAsset *asset, CGSize size, UIImage *image, void (^completion)(UIImage *)) {
    BOOL video = (asset.mediaType == PHAssetMediaTypeVideo);
    BOOL duration = (asset.duration > 0);
    if (!video && !duration)
        return completion(image);
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        CGRect bounds = (CGRect){CGPointZero, size};
        UIGraphicsBeginImageContextWithOptions(bounds.size, YES, 0.0f);
        [image drawInRect:bounds];
        
        CGFloat margin = 5.0f;
        
        if (asset.mediaType == PHAssetMediaTypeVideo) {
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
            
            CGRect boundingBox = CGPathGetPathBoundingBox(videoPath);
            
            UIBezierPath *path = [UIBezierPath bezierPathWithCGPath:videoPath];
            [path applyTransform:CGAffineTransformMakeTranslation(margin, CGRectGetMaxY(bounds) - CGRectGetHeight(boundingBox) - margin)];
            [[UIColor whiteColor] setFill];
            [path fill];
        }
        
        if (asset.duration > 0) {
            NSDate *toDate = [NSDate date];
            NSDate *fromDate = [toDate dateByAddingTimeInterval:(-1.0f * asset.duration)];
            NSCalendarUnit components = (NSCalendarUnit)(NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond | NSCalendarUnitNanosecond);
            NSDateComponents *dateComponents = [[NSCalendar currentCalendar] components:components fromDate:fromDate toDate:toDate options:0];
            NSInteger second = dateComponents.second;
            if (dateComponents.nanosecond >= NSEC_PER_SEC / 2.0f)
                second += 1;
            NSString *durationString = [NSString stringWithFormat:@"%ld:%02ld", (long)dateComponents.minute, (long)second];
            if (dateComponents.hour)
                durationString = [NSString stringWithFormat:@"%ld:%@", (long)dateComponents.hour, durationString];
            
            UIFont *font = [UIFont systemFontOfSize:12.0f];
            NSAttributedString *attributedDuration = [[NSAttributedString alloc] initWithString:durationString attributes:@{NSFontAttributeName: font, NSForegroundColorAttributeName: [UIColor whiteColor]}];
            CGRect boundingRect = [attributedDuration boundingRectWithSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin context:NULL];
            [attributedDuration drawAtPoint:CGPointMake(ceil(CGRectGetMaxX(bounds) - boundingRect.size.width - margin), ceil(CGRectGetMaxY(bounds) - boundingRect.size.height - margin + 2))];
        }
        
        UIImage *result = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(result);
        });
    });
}

#pragma mark - DCAssetCollectionViewCell

@interface DCAssetCollectionViewCell : UICollectionViewCell

@property (nonatomic, strong) UIImageView *backgroundView;
@property (nonatomic, readonly, weak) PHAsset *asset;
@property (nonatomic, weak) PHCachingImageManager *imageManager;
@property (nonatomic) PHImageRequestID request;

@end

@implementation DCAssetCollectionViewCell

@dynamic backgroundView;

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
    
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
    
    UIImageView *backgroundView = [[UIImageView alloc] initWithFrame:CGRectZero];
    backgroundView.contentMode = UIViewContentModeScaleAspectFill;
    backgroundView.clipsToBounds = YES;
    
    self.backgroundView = backgroundView;
    self.selectedBackgroundView = [[UIImageView alloc] initWithImage:selectedImage];

    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    
    [self.imageManager cancelImageRequest:self.request];
    self.request = PHInvalidImageRequestID;
    self.imageManager = nil;
    self.backgroundView.image = nil;
    _asset = nil;
}

- (void)setAsset:(nullable PHAsset *)asset withImageManager:(nullable PHCachingImageManager *)imageManager options:(nullable PHImageRequestOptions *)options {
    BOOL changed = ![_asset isEqual:asset];
    _asset = asset;
    if (!changed)
        return;

    self.backgroundColor = (asset ? [UIColor lightGrayColor] : [UIColor clearColor]);
    self.userInteractionEnabled = !!asset;
    
    self.backgroundView.image = nil;

    if (!asset || !imageManager)
        return;
    
    CGFloat scale = [[UIScreen mainScreen] scale];
    CGSize size = self.backgroundView.bounds.size;
    CGSize targetSize = CGSizeApplyAffineTransform(size, CGAffineTransformMakeScale(scale, scale));
    
    [imageManager cancelImageRequest:self.request];
    self.imageManager = imageManager;
    self.request = [imageManager requestImageForAsset:asset targetSize:targetSize contentMode:PHImageContentModeAspectFill options:options resultHandler:^(UIImage * __nullable result, NSDictionary * __nullable info) {
        self.imageManager = nil;
        self.request = PHInvalidImageRequestID;
        if ([info[PHImageCancelledKey] boolValue])
            return;
        
        DCOverylayDetailsOnPHAssetImage(asset, size, result, ^(UIImage *image) {
            if ([self.asset isEqual:asset]) {
                self.backgroundView.image = image;
            }
        });
    }];
}

@end

#pragma mark - DCAssetCollectionViewFlowLayout

@interface DCAssetCollectionViewFlowLayout : UICollectionViewFlowLayout

@end

@implementation DCAssetCollectionViewFlowLayout {
    NSNumber *_previousItem;
}

- (instancetype)init {
    self = [super init];
    if (!self)
        return nil;
    
    self.minimumLineSpacing = 1.0f;
    self.minimumInteritemSpacing = 1.0f;
    
    return self;
}

- (void)prepareLayout {
    UICollectionView *collectionView = self.collectionView;
    CGFloat minimumInteritemSpacing = self.minimumInteritemSpacing;
    CGFloat minimumLineSpacing = self.minimumLineSpacing;
    CGSize itemSize = self.itemSize;

    BOOL initial = CGSizeEqualToSize(collectionView.contentSize, CGSizeZero);
    
    NSUInteger row = floor((collectionView.contentOffset.y + collectionView.contentInset.top) / (itemSize.height + minimumLineSpacing));
    _previousItem = @(row * (NSUInteger)floor(collectionView.contentSize.width / itemSize.width));

    CGFloat width = CGRectGetWidth(collectionView.bounds);
    NSUInteger itemsPerRow = (NSUInteger)floor(width / 80.0f);
    CGFloat itemWidth = floor((width - ((itemsPerRow - 1) * minimumInteritemSpacing)) / itemsPerRow);
    self.itemSize = CGSizeMake(itemWidth, itemWidth);
    
    [super prepareLayout];
    
    if (initial) {
        [collectionView setContentOffset:CGPointMake(0, MAX(MIN(0, -collectionView.contentInset.top), self.collectionViewContentSize.height - CGRectGetHeight(collectionView.bounds) - 64)) animated:NO];
    }
}

- (CGPoint)targetContentOffsetForProposedContentOffset:(CGPoint)proposedContentOffset {
    UICollectionView *collectionView = self.collectionView;
    CGSize itemSize = self.itemSize;
    CGFloat minimumLineSpacing = self.minimumLineSpacing;
    CGSize contentSize = self.collectionViewContentSize;
    
    CGFloat width = CGRectGetWidth(collectionView.bounds);
    NSUInteger itemsPerRow = (NSUInteger)floor(width / 80.0f);
    NSUInteger row = (_previousItem ? _previousItem.unsignedIntegerValue : [collectionView numberOfItemsInSection:0] - 1) / itemsPerRow;
    CGFloat proposedOffset = (row * (itemSize.height + minimumLineSpacing) - minimumLineSpacing);
    return CGPointMake(0, MIN(MAX(MIN(0, -collectionView.contentInset.top), proposedOffset), contentSize.height - CGRectGetHeight(collectionView.bounds)));
}

- (UICollectionViewFlowLayoutInvalidationContext *)invalidationContextForBoundsChange:(CGRect)newBounds {
    UICollectionViewFlowLayoutInvalidationContext *context = (UICollectionViewFlowLayoutInvalidationContext *)[super invalidationContextForBoundsChange:newBounds];
    if (CGRectGetWidth(newBounds) != CGRectGetWidth(self.collectionView.bounds)) {
        context.invalidateFlowLayoutDelegateMetrics = YES;
    }
    return context;
}

@end

#pragma mark - DCAssetCollectionFooterView

@interface DCAssetCollectionFooterView : UICollectionReusableView

@property (nonatomic, readonly) UILabel *summaryLabel;

- (void)setFetchResult:(PHFetchResult<PHAsset *> *)fetchResult;

@end

@implementation DCAssetCollectionFooterView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
    
    UILabel *summaryLabel = [[UILabel alloc] init];
    [self addSubview:summaryLabel];
    _summaryLabel = summaryLabel;
    
    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    UILabel *summaryLabel = self.summaryLabel;
    [summaryLabel sizeToFit];
    
    CGRect bounds = self.bounds;
    summaryLabel.center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
}

- (void)setFetchResult:(PHFetchResult<PHAsset *> *)fetchResult {
    NSMutableArray<NSString *> *components = [NSMutableArray new];
    NSUInteger numberOfPhotos = [fetchResult countOfAssetsWithMediaType:PHAssetMediaTypeImage];
    if (numberOfPhotos)
        [components addObject:[NSString stringWithFormat:@"%lu Photos", (unsigned long)numberOfPhotos]];
    
    NSUInteger numberOfVideos = [fetchResult countOfAssetsWithMediaType:PHAssetMediaTypeVideo];
    if (numberOfVideos)
        [components addObject:[NSString stringWithFormat:@"%lu Videos", (unsigned long)numberOfVideos]];
    
    self.summaryLabel.text = [components componentsJoinedByString:@", "];
}

@end

#pragma mark - DCAssetCollectionViewController

@interface DCAssetCollectionViewController : UICollectionViewController <PHPhotoLibraryChangeObserver>

@property (nonatomic, readonly) UICollectionViewFlowLayout *collectionViewLayout;

@property (nonatomic, readonly, strong) PHAssetCollection *collection;
@property (nonatomic, readonly, strong) PHFetchResult<PHAsset *> *assets;
@property (nonatomic, readonly, strong) PHCachingImageManager *imageManager;
@property (nonatomic, readonly, strong) PHImageRequestOptions *requestOptions;

@property (nonatomic, copy) NSArray<NSString *> *mediaTypes;

@property (nonatomic) BOOL finished;
@property (nonatomic) CGSize previousItemSize;

- (instancetype)initWithAssetCollection:(PHAssetCollection *)collection mediaTypes:(NSArray<NSString *> *)mediaTypes;

@end

static NSString * const DCAssetCollectionViewCellIdentifier = @"DCAssetCollectionViewCellIdentifier";
static NSString * const DCAssetCollectionFooterViewIdentifier = @"DCAssetCollectionFooterViewIdentifier";

@implementation DCAssetCollectionViewController

@dynamic collectionViewLayout;

- (DCImagePickerController *)imagePickerController {
    return (DCImagePickerController *)self.navigationController;
}

- (instancetype)initWithAssetCollection:(PHAssetCollection *)collection mediaTypes:(NSArray<NSString *> *)mediaTypes {
    self = [super initWithCollectionViewLayout:[DCAssetCollectionViewFlowLayout new]];
    if (!self)
        return nil;
    
    _collection = collection;
    _mediaTypes = [mediaTypes copy];
    _imageManager = [[PHCachingImageManager alloc] init];
    
    _requestOptions = [PHImageRequestOptions new];
    _requestOptions.deliveryMode = PHImageRequestOptionsDeliveryModeOpportunistic;
    _requestOptions.resizeMode = PHImageRequestOptionsResizeModeFast;
    _requestOptions.networkAccessAllowed = YES;

    UIBarButtonItem *item = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(done)];
    item.style = UIBarButtonItemStyleDone;
    self.navigationItem.rightBarButtonItem = item;

    [self updateAssets];
    [self numberOfSelectedItemsChanged];
    
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    
    return self;
}

- (void)dealloc {
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

- (void)setMediaTypes:(NSArray<NSString *> *)mediaTypes {
    BOOL changed = ![_mediaTypes isEqualToArray:mediaTypes];
    _mediaTypes = [mediaTypes copy];
    if (changed)
        [self updateAssets];
}

- (void)updateAssets {
    PHFetchOptions *options = [PHFetchOptions new];
    options.predicate = DCMediaTypePredicateFromMediaTypes(self.mediaTypes);
    options.wantsIncrementalChangeDetails = NO;
    
    _assets = [PHAsset fetchAssetsInAssetCollection:_collection options:options];
    
    if ([self isViewLoaded]) {
        [self.collectionView reloadData];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    UICollectionView *collectionView = self.collectionView;
    collectionView.backgroundColor = [UIColor whiteColor];
    collectionView.allowsMultipleSelection = YES;
    collectionView.alwaysBounceVertical = YES;

    [collectionView registerClass:[DCAssetCollectionViewCell class] forCellWithReuseIdentifier:DCAssetCollectionViewCellIdentifier];
    [collectionView registerClass:[DCAssetCollectionFooterView class] forSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:DCAssetCollectionFooterViewIdentifier];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    CGSize itemSize = self.collectionViewLayout.itemSize;
    if (!CGSizeEqualToSize(self.previousItemSize, itemSize)) {
        NSUInteger preloadSize = MIN(_assets.count, 100);
        NSArray<PHAsset *> *assetsToPreload = [_assets objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(_assets.count - preloadSize, preloadSize)]];

        CGFloat scale = [[UIScreen mainScreen] scale];
        CGSize size = CGSizeApplyAffineTransform(itemSize, CGAffineTransformMakeScale(scale, scale));
        [_imageManager stopCachingImagesForAllAssets];
        [_imageManager startCachingImagesForAssets:assetsToPreload targetSize:size contentMode:PHImageContentModeAspectFill options:_requestOptions];
    }
    
    self.previousItemSize = itemSize;
}

- (void)willMoveToParentViewController:(nullable UIViewController *)parent {
    [super willMoveToParentViewController:parent];
    if (!parent)
        return;
    
    NSUInteger selectedItems = (self.isViewLoaded ? self.collectionView.indexPathsForSelectedItems.count : 0);
    DCImagePickerController *imagePickerController = (DCImagePickerController *)parent;
    self.navigationItem.rightBarButtonItem.enabled = (selectedItems >= imagePickerController.minimumNumberOfItems && selectedItems <= imagePickerController.maximumNumberOfItems);
}

- (void)done {
    NSMutableIndexSet *selectedIndexes = [NSMutableIndexSet new];
    for (NSIndexPath *indexPath in self.collectionView.indexPathsForSelectedItems)
        [selectedIndexes addIndex:indexPath.item];
    
    NSArray<PHAsset *> *selectedAssets = [_assets objectsAtIndexes:selectedIndexes];
    [self.imagePickerController finishedWithAssets:selectedAssets];
    
    UIActivityIndicatorView *indicatorView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    [indicatorView startAnimating];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:indicatorView];
    self.finished = YES;
}

- (void)numberOfSelectedItemsChanged {
    NSUInteger selectedItems = (self.isViewLoaded ? self.collectionView.indexPathsForSelectedItems.count : 0);
    self.title = (selectedItems > 0 ? [NSString stringWithFormat:@"%lu Selected", (unsigned long)selectedItems] : _collection.localizedTitle);
    
    DCImagePickerController *imagePickerController = self.imagePickerController;
    self.navigationItem.rightBarButtonItem.enabled = (selectedItems >= imagePickerController.minimumNumberOfItems && (selectedItems <= imagePickerController.maximumNumberOfItems || imagePickerController.maximumNumberOfItems == 0));
}

#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateAssets];
    });
}

#pragma mark UICollectionViewDelegate

- (BOOL)collectionView:(UICollectionView *)collectionView shouldSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    return !self.finished;
}

- (BOOL)collectionView:(UICollectionView *)collectionView shouldDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
    return !self.finished;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self numberOfSelectedItemsChanged];
}

- (void)collectionView:(UICollectionView *)collectionView didDeselectItemAtIndexPath:(NSIndexPath *)indexPath {
    [self numberOfSelectedItemsChanged];
}

#pragma mark - UICollectionViewDelegateFlowLayout

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout referenceSizeForFooterInSection:(NSInteger)section {
    return CGSizeMake(0, 68);
}

#pragma mark UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return self.assets.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    DCAssetCollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:DCAssetCollectionViewCellIdentifier forIndexPath:indexPath];
    PHAsset *asset = (indexPath.item < self.assets.count ? [self.assets objectAtIndex:indexPath.item] : nil);
    [cell setAsset:asset withImageManager:_imageManager options:_requestOptions];
    return cell;
}

- (UICollectionReusableView *)collectionView:(UICollectionView *)collectionView viewForSupplementaryElementOfKind:(NSString *)kind atIndexPath:(NSIndexPath *)indexPath {
    DCAssetCollectionFooterView *footerView = [collectionView dequeueReusableSupplementaryViewOfKind:UICollectionElementKindSectionFooter withReuseIdentifier:DCAssetCollectionFooterViewIdentifier forIndexPath:indexPath];
    [footerView setFetchResult:_assets];
    return footerView;
}

@end

#pragma mark - DCCollectionTableViewCell

@interface DCCollectionTableViewCell : UITableViewCell

@property (nonatomic, readonly, nullable) PHCollection *collection;

@end

@implementation DCCollectionTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(nullable NSString *)reuseIdentifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:reuseIdentifier];
    if (!self)
        return nil;
    
    self.textLabel.font = [UIFont systemFontOfSize:17.0f];
    self.detailTextLabel.font = [UIFont systemFontOfSize:13.0f];
    self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect frame = self.detailTextLabel.frame;
    frame.origin.y += 5;
    self.detailTextLabel.frame = frame;
}

- (void)setCollection:(nullable PHCollection *)collection mediaTypes:(NSArray<NSString *> *)mediaTypes {
    _collection = collection;
    self.textLabel.text = collection.localizedTitle;
    self.imageView.contentMode = UIViewContentModeCenter;
    
    if (![collection isKindOfClass:[PHAssetCollection class]])
        return;
    
    PHAssetCollection *assetCollection = (PHAssetCollection *)collection;
    
    NSUInteger assetCount = assetCollection.estimatedAssetCount;
    if (assetCount == NSNotFound) {
        PHFetchOptions *options = [PHFetchOptions new];
        options.predicate = DCMediaTypePredicateFromMediaTypes(mediaTypes);
        options.wantsIncrementalChangeDetails = NO;
        assetCount = [[PHAsset fetchAssetsInAssetCollection:assetCollection options:options] count];
    }
    
    self.detailTextLabel.text = [NSNumberFormatter localizedStringFromNumber:@(assetCount) numberStyle:NSNumberFormatterDecimalStyle];
    
    // Fetch the first three assets from the collection
    PHFetchOptions *options = [PHFetchOptions new];
    options.wantsIncrementalChangeDetails = NO;
    const NSUInteger fetchLimit = 3;
    
    PHFetchResult<PHAsset *> *result = nil;
    if ([options respondsToSelector:@selector(setFetchLimit:)]) {
        options.fetchLimit = fetchLimit;
        result = [PHAsset fetchKeyAssetsInAssetCollection:assetCollection options:options];
    } else {
        // On iOS 8, -fetchKeyAssetsInAssetCollection:options: doesn't appear to return any results
        result = [PHAsset fetchAssetsInAssetCollection:assetCollection options:options];
    }
    
    CGFloat width = 68.0f;
    CGFloat height = width + 6.0f;
    CGFloat scale = [[UIScreen mainScreen] scale];
    
    // Fetch thumbnails for the first three assets
    PHImageRequestOptions *imageOptions = [PHImageRequestOptions new];
    imageOptions.networkAccessAllowed = YES;
    imageOptions.deliveryMode = PHImageRequestOptionsDeliveryModeFastFormat;
    imageOptions.resizeMode = PHImageRequestOptionsResizeModeExact;
    
    NSPointerArray *images = [NSPointerArray strongObjectsPointerArray];
    images.count = result.count;
    
    dispatch_group_t group = dispatch_group_create();

    [result enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger index, BOOL * __nonnull stop) {
        CGSize size = CGSizeApplyAffineTransform(CGSizeMake(width, height), CGAffineTransformMakeScale(scale, scale));
        dispatch_group_enter(group);
        [[PHImageManager defaultManager] requestImageForAsset:asset targetSize:size contentMode:PHImageContentModeAspectFill options:imageOptions resultHandler:^(UIImage * __nullable result, NSDictionary * __nullable info) {
            [images replacePointerAtIndex:index withPointer:(__bridge void *)result];
            dispatch_group_leave(group);
        }];
        
        if (index == (fetchLimit - 1))
            *stop = YES;
    }];
    
    // Draw the first three thumbnails one on top of the other to appear like a stack
    dispatch_group_notify(group, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        CGContextRef context = CGBitmapContextCreate(NULL, width * scale, height * scale, 8, sizeof(UInt32) * width * scale, colorSpace, kCGBitmapByteOrder32Big |kCGImageAlphaPremultipliedLast);
        CGContextTranslateCTM(context, 0.0f, height * scale);
        CGContextScaleCTM(context, scale, -scale);
        
        [images.allObjects enumerateObjectsUsingBlock:^(UIImage * __nonnull obj, NSUInteger idx, BOOL * __nonnull stop) {
            CGImageRef image = obj.CGImage;
            CGContextSaveGState(context);
            
            CGSize imageSize = CGSizeMake(CGImageGetWidth(image), CGImageGetHeight(image));
            CGRect clipRect = CGRectMake(idx * 2.0f, (2 - idx) * 3.0f, width - idx * 4.0f, idx == 0 ? width : 2.0f);
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
        }];
        
        CGImageRef imageRef = CGBitmapContextCreateImage(context);
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
        
        UIImage *image = [UIImage imageWithCGImage:imageRef scale:scale orientation:UIImageOrientationUp];;
        CGImageRelease(imageRef);

        dispatch_async(dispatch_get_main_queue(), ^{
            if (![self.collection isEqual:collection])
                return;
            
            self.imageView.image = image;
            [self setNeedsLayout];
        });
    });
}

@end

#pragma mark - DCCollectionListTableViewController

@interface DCCollectionListTableViewController : UITableViewController <PHPhotoLibraryChangeObserver>

@property (nonatomic, readonly) DCImagePickerController *imagePickerController;
@property (nonatomic, copy) NSArray<NSString *> *mediaTypes;
@property (nonatomic, readonly, strong) NSArray<PHCollection *> *collections;

@end

static NSString * const DCCollectionTableViewCellIdentifier = @"DCCollectionTableViewCellIdentifier";

@implementation DCCollectionListTableViewController

- (DCImagePickerController *)imagePickerController {
    return (DCImagePickerController *)self.navigationController;
}

- (instancetype)initWithMediaTypes:(NSArray<NSString *> *)mediaTypes {
    self = [super initWithStyle:UITableViewStylePlain];
    if (!self)
        return nil;
    
    _mediaTypes = [mediaTypes copy];
    
    self.title = @"Photos";
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self.imagePickerController action:@selector(cancel)];
    
    [self updateCollections];
    
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
    
    return self;
}

- (void)dealloc {
    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
}

- (void)setMediaTypes:(NSArray<NSString *> *)mediaTypes {
    BOOL changed = ![_mediaTypes isEqualToArray:mediaTypes];
    _mediaTypes = [mediaTypes copy];
    if (changed)
        [self updateCollections];
}

- (void)updateCollections {
    PHFetchOptions *options = [PHFetchOptions new];
    options.wantsIncrementalChangeDetails = NO;
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(startDate)) ascending:YES]];
    
    NSMutableArray<PHCollection *> *collections = [NSMutableArray new];
    
    NSMutableArray<NSNumber *> *excludedSubtypes = [[NSMutableArray alloc] initWithObjects:
                                                    @(PHAssetCollectionSubtypeSmartAlbumFavorites),
                                                    @(PHAssetCollectionSubtypeSmartAlbumAllHidden),
                                                    @(PHAssetCollectionSubtypeSmartAlbumRecentlyAdded), nil];
    
    NSArray<NSString *> *mediaTypes = self.mediaTypes;
    if (![mediaTypes containsObject:(id)kUTTypeImage]) {
        [excludedSubtypes addObjectsFromArray:@[@(PHAssetCollectionSubtypeSmartAlbumPanoramas),
                                                @(PHAssetCollectionSubtypeSmartAlbumBursts),
                                                @(PHAssetCollectionSubtypeSmartAlbumPanoramas),
                                                @(PHAssetCollectionSubtypeSmartAlbumSelfPortraits),
                                                @(PHAssetCollectionSubtypeSmartAlbumScreenshots),
                                                @(PHAssetCollectionSubtypeSmartAlbumPanoramas),
                                                @(PHAssetCollectionSubtypeSmartAlbumPanoramas),
                                                @(PHAssetCollectionSubtypeSmartAlbumPanoramas),
                                                @(PHAssetCollectionSubtypeSmartAlbumPanoramas),
                                                @(PHAssetCollectionSubtypeSmartAlbumPanoramas)]];
    }
    if (![mediaTypes containsObject:(id)kUTTypeMovie]) {
        [excludedSubtypes addObjectsFromArray:@[@(PHAssetCollectionSubtypeSmartAlbumVideos),
                                                @(PHAssetCollectionSubtypeSmartAlbumTimelapses),
                                                @(PHAssetCollectionSubtypeSmartAlbumSlomoVideos)]];
    }
    
    PHFetchResult *smartAlbums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeAny options:options];
    for (PHAssetCollection *smartAlbum in smartAlbums) {
        if ([excludedSubtypes containsObject:@(smartAlbum.assetCollectionSubtype)])
            continue;
        
        PHFetchOptions *options = [PHFetchOptions new];
        options.wantsIncrementalChangeDetails = NO;
        if (![[PHAsset fetchAssetsInAssetCollection:smartAlbum options:options] count])
            continue;
        
        [collections addObject:smartAlbum];
    }
    
    NSArray<NSNumber *> *sortedSubtypes = @[@(PHAssetCollectionSubtypeSmartAlbumUserLibrary),
                                            @(PHAssetCollectionSubtypeSmartAlbumSelfPortraits),
                                            @(PHAssetCollectionSubtypeSmartAlbumPanoramas),
                                            @(PHAssetCollectionSubtypeSmartAlbumVideos),
                                            @(PHAssetCollectionSubtypeSmartAlbumSlomoVideos),
                                            @(PHAssetCollectionSubtypeSmartAlbumBursts),
                                            @(PHAssetCollectionSubtypeSmartAlbumScreenshots)];
    
    [collections sortUsingComparator:^NSComparisonResult(PHAssetCollection *obj1, PHAssetCollection *obj2) {
        return [@([sortedSubtypes indexOfObject:@(obj1.assetCollectionSubtype)]) compare:@([sortedSubtypes indexOfObject:@(obj2.assetCollectionSubtype)])];
    }];
    
    PHFetchResult *albums = [PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeAlbum subtype:PHAssetCollectionSubtypeAny options:options];
    for (PHCollection *album in albums)
        [collections addObject:album];
    
    _collections = [collections copy];
    
    if ([self isViewLoaded]) {
        [self.tableView reloadData];
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.rowHeight = 86.0f;
    self.tableView.separatorColor = [UIColor clearColor];
    [self.tableView registerClass:[DCCollectionTableViewCell class] forCellReuseIdentifier:DCCollectionTableViewCellIdentifier];
}

#pragma mark - PHPhotoLibraryChangeObserver

- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateCollections];
    });
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.collections.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    DCCollectionTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:DCCollectionTableViewCellIdentifier forIndexPath:indexPath];
    [cell setCollection:[self.collections objectAtIndex:indexPath.row] mediaTypes:self.mediaTypes];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PHCollection *collection = [self.collections objectAtIndex:indexPath.row];
    
    DCAssetCollectionViewController *viewController = [[DCAssetCollectionViewController alloc] initWithAssetCollection:(PHAssetCollection *)collection mediaTypes:self.mediaTypes];
    [self.navigationController pushViewController:viewController animated:YES];
}

@end

#pragma mark - DCImagePickerPermissionsViewController

@interface DCImagePickerPermissionsViewController : UIViewController

@property (nonatomic, readonly, weak) UIImageView *lockImageView;
@property (nonatomic, readonly, weak) UILabel *titleLabel;
@property (nonatomic, readonly, weak) UILabel *subtitleLabel;

@end

@implementation DCImagePickerPermissionsViewController

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self)
        return nil;
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:@selector(cancel)];
    
    return self;
}

- (void)cancel {
    [(DCImagePickerController *)self.navigationController cancel];
}

- (void)loadView {
    [super loadView];
    
    UIView *view = self.view;
    
    CGRect bounds = CGRectMake(0, 0, 95, 125);
    UIGraphicsBeginImageContextWithOptions(bounds.size, NO, 0.0f);
    [[UIColor blackColor] setFill];
    [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 56, 95, 69) cornerRadius:6.0f] fill];
    [[UIColor blackColor] setStroke];
    UIBezierPath *loopPath = [UIBezierPath bezierPath];
    [loopPath setLineWidth:14];
    [loopPath moveToPoint:CGPointMake(20, 56)];
    [loopPath addArcWithCenter:CGPointMake(47.5, 36) radius:27.5 startAngle:M_PI endAngle:0 clockwise:YES];
    [loopPath addLineToPoint:CGPointMake(75, 56)];
    [loopPath stroke];
    UIImage *lockImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    UIImageView *lockImageView = [[UIImageView alloc] init];
    lockImageView.image = lockImage;
    lockImageView.layer.shadowRadius = 2.0f;
    lockImageView.layer.shadowOpacity = 0.1f;
    lockImageView.layer.shadowOffset = CGSizeMake(0, 2);
    [view addSubview:lockImageView];
    _lockImageView = lockImageView;
    
    UIColor *textColor = [UIColor colorWithRed:0.5f green:0.53f blue:0.58f alpha:1.0f];
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.numberOfLines = 0;
    titleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
    titleLabel.textColor = textColor;
    titleLabel.text = @"This app does not have access to your photos or videos.";
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [view addSubview:titleLabel];
    _titleLabel = titleLabel;
    
    UILabel *subtitleLabel = [[UILabel alloc] init];
    subtitleLabel.numberOfLines = 0;
    subtitleLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
    subtitleLabel.textColor = textColor;
    subtitleLabel.text = @"You can enable access in Privacy Settings.";
    subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [view addSubview:subtitleLabel];
    _subtitleLabel = subtitleLabel;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    
    UIImageView *lockImageView = self.lockImageView;
    UILabel *titleLabel = self.titleLabel;
    UILabel *subtitleLabel = self.subtitleLabel;
    
    CGRect bounds = self.view.bounds;
    CGSize lockSize = lockImageView.intrinsicContentSize;
    CGSize titleSize = [titleLabel sizeThatFits:CGSizeMake(CGRectGetWidth(bounds) - 20, CGFLOAT_MAX)];
    CGSize subtitleSize = [subtitleLabel sizeThatFits:CGSizeMake(CGRectGetWidth(bounds) - 20, CGFLOAT_MAX)];

    CGFloat offsetY = ((CGRectGetHeight(bounds) - lockSize.height - 25 - titleSize.height - 8 - subtitleSize.height) / 2.0f);
    lockImageView.frame = CGRectIntegral((CGRect){CGPointMake(CGRectGetMidX(bounds) - lockSize.width / 2.0f, offsetY), lockSize});
    
    offsetY += lockSize.height + 25;
    titleLabel.frame = CGRectIntegral((CGRect){CGPointMake(CGRectGetMidX(bounds) - titleSize.width / 2.0f, offsetY), titleSize});
    
    offsetY += titleSize.height + 8;
    subtitleLabel.frame = CGRectIntegral((CGRect){CGPointMake(CGRectGetMidX(bounds) - subtitleSize.width / 2.0f, offsetY), subtitleSize});
}

@end

#pragma mark - DCImagePickerController

NSString * const DCImagePickerControllerAsset = @"DCImagePickerControllerAsset";

@implementation DCImagePickerController

@dynamic delegate;

+ (BOOL)isSourceTypeAvailable:(DCImagePickerControllerSourceType)sourceType {
    if (sourceType == DCImagePickerControllerSourceTypePhotoLibrary || sourceType == DCImagePickerControllerSourceTypeSavedPhotosAlbum) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        return (status == PHAuthorizationStatusNotDetermined || status == PHAuthorizationStatusAuthorized);
    } 

    return NO;
}

+ (NSArray *)availableMediaTypesForSourceType:(DCImagePickerControllerSourceType)sourceType {
    return @[(id)kUTTypeImage, (id)kUTTypeMovie];
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil {
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self)
        return nil;
    
    self.sourceType = DCImagePickerControllerSourceTypePhotoLibrary;
    self.mediaTypes = [[self class] availableMediaTypesForSourceType:self.sourceType];

    return self;
}

- (void)setSourceType:(DCImagePickerControllerSourceType)sourceType {
    BOOL changed = (_sourceType != sourceType);
    _sourceType = sourceType;
    if (changed && [self isViewLoaded])
        [self updateViewControllers];
}

- (void)setMediaTypes:(NSArray<NSString *> *)mediaTypes {
    _mediaTypes = (mediaTypes.count ? [mediaTypes copy] : [[self class] availableMediaTypesForSourceType:self.sourceType]);
    
    for (UIViewController *viewController in self.viewControllers) {
        if ([viewController isKindOfClass:[DCAssetCollectionViewController class]]) {
            [(DCAssetCollectionViewController *)viewController setMediaTypes:_mediaTypes];
        }
        if ([viewController isKindOfClass:[DCCollectionListTableViewController class]]) {
            [(DCCollectionListTableViewController *)viewController setMediaTypes:_mediaTypes];
        }
    }
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    
    if ([PHPhotoLibrary authorizationStatus] == PHAuthorizationStatusNotDetermined) {
        [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateViewControllers];
            });
        }];
    } else {
        [self updateViewControllers];
    }
}

- (void)updateViewControllers {
    PHAuthorizationStatus authorizationStatus = [PHPhotoLibrary authorizationStatus];
    if (authorizationStatus == PHAuthorizationStatusAuthorized) {
        DCImagePickerControllerSourceType sourceType = self.sourceType;
        if (sourceType == DCImagePickerControllerSourceTypePhotoLibrary) {
            DCCollectionListTableViewController *albumsViewController = [[DCCollectionListTableViewController alloc] initWithMediaTypes:self.mediaTypes];
            [self setViewControllers:@[albumsViewController] animated:NO];
        } else if (sourceType == DCImagePickerControllerSourceTypeSavedPhotosAlbum) {
            PHFetchOptions *options = [PHFetchOptions new];
            options.wantsIncrementalChangeDetails = NO;
            PHAssetCollection *collection = [[PHAssetCollection fetchAssetCollectionsWithType:PHAssetCollectionTypeSmartAlbum subtype:PHAssetCollectionSubtypeSmartAlbumUserLibrary options:options] firstObject];
            if (!collection)
                return;
            
            DCAssetCollectionViewController *collectionViewController = [[DCAssetCollectionViewController alloc] initWithAssetCollection:collection mediaTypes:self.mediaTypes];
            [self setViewControllers:@[collectionViewController] animated:NO];
        }
    } else if (authorizationStatus == PHAuthorizationStatusRestricted || authorizationStatus == PHAuthorizationStatusDenied) {
        DCImagePickerPermissionsViewController *permissionsViewController = [[DCImagePickerPermissionsViewController alloc] init];
        [self setViewControllers:@[permissionsViewController] animated:NO];
    }
}

- (void)setMinimumNumberOfItems:(NSUInteger)minimumNumberOfItems {
    NSParameterAssert(minimumNumberOfItems <= _maximumNumberOfItems || _maximumNumberOfItems == 0);
    _minimumNumberOfItems = minimumNumberOfItems;
}

- (void)setMaximumNumberOfItems:(NSUInteger)maximumNumberOfItems {
    NSParameterAssert(maximumNumberOfItems >= _minimumNumberOfItems || maximumNumberOfItems == 0);
    _maximumNumberOfItems = maximumNumberOfItems;
}

- (void)finishedWithAssets:(NSArray<PHAsset *> *)assets {
    id<DCImagePickerControllerDelegate> delegate = self.delegate;
    if (![delegate respondsToSelector:@selector(dcImagePickerController:didFinishPickingMediaWithInfo:)])
        return;
    
    dispatch_group_t group = dispatch_group_create();
    NSMutableArray<NSDictionary *> *assetInfos = [NSMutableArray new];
    
    [assets enumerateObjectsUsingBlock:^(PHAsset *asset, NSUInteger idx, BOOL *stop) {
        NSMutableDictionary *assetInfo = [[NSMutableDictionary alloc] initWithObjectsAndKeys:asset, DCImagePickerControllerAsset, nil];
        [assetInfos addObject:assetInfo];
        
        NSString *mediaType = DCMediaTypeFromPHAsset(asset);
        if (mediaType)
            [assetInfo setObject:mediaType forKey:UIImagePickerControllerMediaType];
        
        NSURL *referenceURL = DCALAssetURLFromPHAsset(asset);
        if (referenceURL)
            [assetInfo setObject:referenceURL forKey:UIImagePickerControllerReferenceURL];
        
        if (self.originalImageNotRequired)
            return;
        
        PHImageManager *imageManager = [PHImageManager defaultManager];
        
        if (asset.mediaType == PHAssetMediaTypeImage) {
            PHImageRequestOptions *originalOptions = [PHImageRequestOptions new];
            originalOptions.resizeMode = PHImageRequestOptionsResizeModeNone;
            originalOptions.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
            originalOptions.version = PHImageRequestOptionsVersionOriginal;
            originalOptions.networkAccessAllowed = YES;
            
            dispatch_group_enter(group);
            [imageManager requestImageForAsset:asset targetSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) contentMode:PHImageContentModeDefault options:originalOptions resultHandler:^(UIImage * __nullable result, NSDictionary * __nullable info) {
                if (result)
                    [assetInfo setObject:result forKey:UIImagePickerControllerOriginalImage];
                dispatch_group_leave(group);
            }];
            
            PHImageRequestOptions *editedOptions = [originalOptions copy];
            editedOptions.version = PHImageRequestOptionsVersionCurrent;

            dispatch_group_enter(group);
            [imageManager requestImageForAsset:asset targetSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) contentMode:PHImageContentModeDefault options:editedOptions resultHandler:^(UIImage * __nullable result, NSDictionary * __nullable info) {
                if (result)
                    [assetInfo setObject:result forKey:UIImagePickerControllerEditedImage];
                dispatch_group_leave(group);
            }];
            
            dispatch_group_enter(group);
            [imageManager requestImageDataForAsset:asset options:originalOptions resultHandler:^(NSData * __nullable imageData, NSString * __nullable dataUTI, UIImageOrientation orientation, NSDictionary * __nullable info) {
                if (imageData) {
                    NSDictionary *options = [[NSDictionary alloc] initWithObjectsAndKeys:dataUTI, (__bridge id)kCGImageSourceTypeIdentifierHint, nil];
                    CGImageSourceRef imageSource = CGImageSourceCreateWithData((__bridge CFDataRef)imageData, (__bridge CFDictionaryRef)options);
                    if (imageSource) {
                        NSDictionary *metadata = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(imageSource, 0, NULL);
                        [assetInfo setObject:metadata forKey:UIImagePickerControllerMediaMetadata];
                    }
                }
                dispatch_group_leave(group);
            }];
            
            if ([PHLivePhotoRequestOptions class]) {
                PHLivePhotoRequestOptions *livePhotoOptions = [PHLivePhotoRequestOptions new];
                livePhotoOptions.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
                livePhotoOptions.networkAccessAllowed = YES;
                if ([livePhotoOptions respondsToSelector:@selector(setVersion:)])
                    livePhotoOptions.version = PHImageRequestOptionsVersionOriginal;
                
                dispatch_group_enter(group);
                [imageManager requestLivePhotoForAsset:asset targetSize:CGSizeMake(CGFLOAT_MAX, CGFLOAT_MAX) contentMode:PHImageContentModeDefault options:livePhotoOptions resultHandler:^(PHLivePhoto * __nullable livePhoto, NSDictionary * __nullable info) {
                    if (livePhoto)
                        [assetInfo setObject:livePhoto forKey:UIImagePickerControllerLivePhoto];
                    dispatch_group_leave(group);
                }];
            }
        } else if (asset.mediaType == PHAssetMediaTypeVideo) {
            PHVideoRequestOptions *videoOptions = [PHVideoRequestOptions new];
            videoOptions.version = PHVideoRequestOptionsVersionCurrent;
            videoOptions.deliveryMode = PHVideoRequestOptionsDeliveryModeHighQualityFormat;
            videoOptions.networkAccessAllowed = YES;

            dispatch_group_enter(group);
            [imageManager requestAVAssetForVideo:asset options:videoOptions resultHandler:^(AVAsset * __nullable asset, AVAudioMix * __nullable audioMix, NSDictionary * __nullable info) {
                if ([asset isKindOfClass:[AVURLAsset class]]) {
                    [assetInfo setObject:[(AVURLAsset *)asset URL] forKey:UIImagePickerControllerMediaURL];
                }
                dispatch_group_leave(group);
            }];
        }
    }];
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        if (self.cancelled)
            return;
        
        [delegate dcImagePickerController:self didFinishPickingMediaWithInfo:assetInfos];
    });
}

- (void)cancel {
    _cancelled = YES;
    
    id<DCImagePickerControllerDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(dcImagePickerControllerDidCancel:)])
        [delegate dcImagePickerControllerDidCancel:self];
}

@end

NS_ASSUME_NONNULL_END

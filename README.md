# DCImagePickerController

`DCImagePickerController` is a drop-in replacement for `UIImagePickerController` that supports selecting multiple items. It is styled after, and nearly identical to, the `UIImagePickerController` found in iOS 7 and above. It uses `Photos.framework`.

## Example Usage

`DCImagePickerController` works exactly like `UIImagePickerController`, except without any camera functionality and with two new properties, `minimumNumberOfItems` and `maximumNumberOfItems`:

```objc
DCImagePickerController *imagePickerController = [[DCImagePickerController alloc] init];
imagePickerController.minimumNumberOfItems = 2;
imagePickerController.maximumNumberOfItems = 5;
imagePickerController.delegate = self;
imagePickerController.modalPresentationStyle = UIModalPresentationFormSheet;

[self presentViewController:imagePickerController animated:YES completion:nil];
```

## License

DCImagePickerController is available under the MIT license. See the LICENSE file for more info.

//
//  Circlet.xm
//  Circlet
//
//  Created by Julian Weiss on 1/5/14.
//  Copyright (c) 2014 insanj. All rights reserved.
//

#import "CRHeaders.h"
#import "CRNotificationListener.h"
#import "CRView.h"

/******************** SpringBoard (foreground) Methods ********************/

@interface SpringBoard (Circlet)
-(void)circlet_saveCircle:(CRView *)circle toPath:(NSString *)path withWhite:(UIColor *)white black:(UIColor *)black count:(int)count;
-(void)circlet_saveCircle:(CRView *)circle toPath:(NSString *)path withName:(NSString *)name;
@end

%hook SpringBoard
static CRNotificationListener *listener;

-(id)init{
	listener = [CRNotificationListener sharedInstance];
	if(listener.signalEnabled){
		[listener.signalCircle setRadius:(listener.signalPadding / 2.f)];
		[self circlet_saveCircle:listener.signalCircle toPath:@"/private/var/mobile/Library/Circlet/Signal" withWhite:listener.signalWhiteColor black:listener.signalBlackColor count:5];
	}

	if(listener.wifiEnabled){
		[listener.wifiCircle setRadius:(listener.wifiPadding / 2.f)];
		[self circlet_saveCircle:listener.wifiCircle toPath:@"/private/var/mobile/Library/Circlet/Wifi" withWhite:listener.wifiWhiteColor black:listener.signalBlackColor count:3];
		[self circlet_saveCircle:listener.wifiCircle toPath:@"/private/var/mobile/Library/Circlet/Data" withWhite:listener.dataWhiteColor black:listener.dataBlackColor count:1];
	}

	if(listener.batteryEnabled){
		[listener.batteryCircle setRadius:(listener.batteryPadding / 2.f)];
		[self circlet_saveCircle:listener.batteryCircle toPath:@"/private/var/mobile/Library/Circlet/Battery" withWhite:listener.batteryWhiteColor black:listener.batteryBlackColor count:20];
		[self circlet_saveCircle:listener.wifiCircle toPath:@"/private/var/mobile/Library/Circlet/Charging" withWhite:listener.chargingWhiteColor black:listener.chargingBlackColor count:20];
	}

	return %orig();
}

%new -(void)circlet_saveCircle:(CRView *)circle toPath:(NSString *)path withWhite:(UIColor *)white black:(UIColor *)black count:(int)count{
	CRView *whiteCircle = [circle versionWithColor:white];
	CRView *blackCircle = [circle versionWithColor:black];

	NSError *error;
	NSFileManager *fileManager = [[NSFileManager alloc] init];
	[fileManager removeItemAtPath:path error:%error];
	[fileManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&error)

	for(int i = 0; i < count; i++){
		[whiteCircle setState:i withMax:count];
		[blackCircle setState:i withMax:count];

		[self circlet_saveCircle:whiteCircle toPath:path withName:[NSString stringWithFormat:@"/%iWhite@2x.png", i]];
		[self circlet_saveCircle:blackCircle toPath:path withName:[NSString stringWithFormat:@"/%iBlack@2x.png", i]];
	}

	NSLog(@"[Circlet] Wrote %i circle-views to directory: %@", count, [fileManager contentsOfDirectoryAtPath:path error:&error]);
}

%new -(void)circlet_saveCircle:(CRView *)circle toPath:(NSString *)path withName:(NSString *)name{
	UIGraphicsBeginImageContextWithOptions(circle.bounds.size, NO, 0.f);
    [circle.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

	[UIImagePNGRepresentation(image) writeToFile:[path stringByAppendingString:name] atomically:YES];
}

%end

// tomorrow
%new -(_UILegibilityImageSet *)wifiImage:(CRNotificationListener *)listener{
	[listener debugLog:[NSString stringWithFormat:@"Generating wifi image from shared preferences listener: %@", listener]];

	CRView *wifiCircle = listener.wifiCircle;
	CGFloat radius = listener.wifiPadding / 2.f;
	if(wifiCircle.radius != radius)
		[wifiCircle setRadius:radius];

	int networkType = MSHookIvar<int>(self, "_dataNetworkType");
	int wifiState = MSHookIvar<int>(self, "_wifiStrengthBars");
	[listener debugLog:[NSString stringWithFormat:@"WifiStrength Bars:%i", wifiState]];
	if(networkType == 5)
		[wifiCircle setState:wifiState withMax:3];
	else
		[wifiCircle setState:1 withMax:1];

	UIColor *white = (networkType == 5)?listener.wifiWhiteColor:listener.dataWhiteColor;
	UIColor *black = (networkType == 5)?listener.wifiBlackColor:listener.dataBlackColor;

	UIImage *image = [self imageFromCircle:[wifiCircle versionWithColor:white]];
	UIImage *shadow = [self imageFromCircle:[wifiCircle versionWithColor:black]];

	[listener debugLog:[NSString stringWithFormat:@"Created Data Circle view with radius:%f, type:%i, strength:%i, lightColor:%@, and darkColor:%@", radius, networkType, wifiState, image, shadow]];

	return [%c(_UILegibilityImageSet) imageFromImage:image withShadowImage:shadow];
}

%new -(_UILegibilityImageSet *)batteryImage:(CRNotificationListener *)listener{
	[listener debugLog:@"Dealing with old battery view's symbol management"];

	CRView *batteryCircle = listener.batteryCircle;
	CGFloat radius = listener.batteryPadding / 2.f;
	if(batteryCircle.radius != radius)
		[batteryCircle setRadius:radius];

	CGFloat capacity = MSHookIvar<int>(self, "_capacity");
	[batteryCircle setState:capacity withMax:100];

	int state = MSHookIvar<int>(self, "_state");
	UIColor *white = (state != 0)?listener.chargingWhiteColor:listener.batteryWhiteColor;
	UIColor *black = (state != 0)?listener.chargingBlackColor:listener.batteryBlackColor;

	UIImage *image = [%c(SpringBoard) imageFromCircle:[batteryCircle versionWithColor:white]];
	UIImage *shadow = [%c(SpringBoard) imageFromCircle:[batteryCircle versionWithColor:black]];

	[listener debugLog:[NSString stringWithFormat:@"Created Battery Circle view with radius:%f, capacity:%f, state:%i, lightColor:%@, and darkColor:%@", radius, capacity, state, image, shadow]];
	return [%c(_UILegibilityImageSet) imageFromImage:image withShadowImage:shadow];
}

%end

/**************************** StatusBar Image Replacment  ****************************/

%hook UIStatusBarItemView
static char kCRItemViewListenerKey, kCRItemViewCurrentImageskey;

-(id)initWithItem:(id)arg1 data:(id)arg2 actions:(int)arg3 style:(id)arg4{
	UIStatusBarItemView *o = %orig();
	[[NSDistributedNotificationCenter defaultCenter] addObserver:o selector:@selector(setCRLegibilityImages:) name:@"CRSharedListener" object:nil];
	return o;
}

%new -(void)setCRLegibilityImages:(NSNotification *)notification{
	NSDictionary *userInfo = [notification userInfo];
	objc_setAssociatedObject(self, &kCRItemViewListenerKey, [userInfo objectForKey:@"CRListener"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kCRItemViewCurrentImageskey, [userInfo objectForKey:@"CRCurrentImages"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

-(BOOL)updateForNewData:(id)arg1 actions:(int)arg2{
	BOOL should = %orig();
	if(should)
		[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"CRSendImages" object:nil];
	return should;
}

-(_UILegibilityImageSet *)contentsImage{
	NSString *currClass = NSStringFromClass([self class]);
	CRNotificationListener *listener = objc_getAssociatedObject(self, &kCRItemViewListenerKey);
	NSDictionary *dict = objc_getAssociatedObject(self, &kCRItemViewCurrentImageskey);

	if([listener enabledForClassname:currClass]){
		UIColor *textColor = [[self foregroundStyle] textColorForStyle:[self legibilityStyle]];
		_UILegibilityImageSet *set = [dict objectForKey:currClass];

		CGFloat w, a;
		[textColor getWhite:&w alpha:&a];

		if(w < 0.5f)
			return [%c(_UILegibilityImageSet) imageFromImage:[set shadowImage] withShadowImage:[set image]];
		else
			return set;
	}

	return %orig();
}
%end

/**************************** Item View Spacing  ****************************/

%hook UIStatusBarLayoutManager
static char kCRLayoutManagerListenerKey, kCRLayoutManagerCurrentImageskey;
CGFloat signalWidth;

-(id)initWithRegion:(int)arg1 foregroundView:(id)arg2{
	UIStatusBarLayoutManager *o = %orig();
	[[NSDistributedNotificationCenter defaultCenter] addObserver:o selector:@selector(setCRFrameLegibilityImages:) name:@"CRSharedListener" object:nil];
	return o;
}

%new -(void)setCRFrameLegibilityImages:(NSNotification *)notification{
	NSDictionary *userInfo = [notification userInfo];
	objc_setAssociatedObject(self, &kCRLayoutManagerListenerKey, [userInfo objectForKey:@"CRListener"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	objc_setAssociatedObject(self, &kCRLayoutManagerCurrentImageskey, [userInfo objectForKey:@"CRCurrentImages"], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

-(CGRect)_frameForItemView:(UIStatusBarItemView *)arg1 startPosition:(float)arg2{
	[[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"CRSendImages" object:nil];
	
	CRNotificationListener *listener = objc_getAssociatedObject(self, &kCRLayoutManagerListenerKey);
	NSDictionary *dict = objc_getAssociatedObject(self, &kCRLayoutManagerCurrentImageskey);

	if([arg1 isKindOfClass:%c(UIStatusBarSignalStrengthItemView)]){
		if([listener enabledForClassname:@"UIStatusBarSignalStrengthItemView"]){
			[listener debugLog:[NSString stringWithFormat:@"Changing the spacing for statusbar item: %@ (from %@)", arg1, NSStringFromCGRect(%orig())]];

			_UILegibilityImageSet *signalSet = [dict objectForKey:@"UIStatusBarSignalStrengthItemView"];
			UIImage *image = [signalSet image];
			signalWidth = image.size.width;
			return CGRectMake(%orig().origin.x, ceilf(listener.signalPadding / 2.25f), image.size.width * 2, image.size.height * 2);
		}
		
		signalWidth = %orig().size.width;
	}

	else if([arg1 isKindOfClass:%c(UIStatusBarServiceItemView)])
		signalWidth += %orig().size.width + 5.f;

	else if([arg1 isKindOfClass:%c(UIStatusBarDataNetworkItemView)] && [listener enabledForClassname:@"UIStatusBarDataNetworkItemView"]){
		[listener debugLog:[NSString stringWithFormat:@"Changing the spacing for statusbar item: %@ from (%@)", arg1, NSStringFromCGRect(%orig())]];

		_UILegibilityImageSet *wifiSet = [dict objectForKey:@"UIStatusBarDataNetworkItemView"];
		CGFloat diameter = [wifiSet image].size.height * 2;
		return CGRectMake(ceilf(signalWidth + diameter  + 1.f), ceilf(listener.wifiPadding / 2.25f), diameter, diameter);
	}

	else if([arg1 isKindOfClass:%c(UIStatusBarBatteryItemView)] && [listener enabledForClassname:@"UIStatusBarDataNetworkItemView"]){
		[listener debugLog:[NSString stringWithFormat:@"Changing the spacing for statusbar item: %@ from (%@)", arg1, NSStringFromCGRect(%orig())]];

		_UILegibilityImageSet *batterySet = [dict objectForKey:@"UIStatusBarBatteryItemView"];
		CGFloat diameter = [batterySet image].size.height * 2;
		
		int state = MSHookIvar<int>(arg1, "_state");
		if(state != 0)
			[[[arg1 subviews] lastObject] setHidden:YES];

		return CGRectMake(%orig().origin.x, ceilf(listener.batteryPadding / 2.25f), diameter, diameter);;
	}

	return %orig();
}
%end
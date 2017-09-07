//
//  QQAPI.m
//  RNThirdShareMangager
//
//  Created by LvBingru on 10/10/15.
//  Copyright © 2015 erica. All rights reserved.
//

#import "RCTQQAPI.h"
#import <TencentOpenAPI/TencentOAuth.h>
#import <TencentOpenAPI/TencentOAuthObject.h>
#import <TencentOpenAPI/QQApiInterface.h>
#import <TencentOpenAPI/QQApiInterfaceObject.h>

#import <React/RCTLog.h>
#import <React/RCTBridge.h>
#import <React/RCTEventDispatcher.h>
#import <React/RCTImageLoader.h>

//#define NOT_REGISTERED (@"registerApp required.")
#define INVOKE_FAILED (@"QQ API invoke returns false.")

@interface RCTQQAPI()<QQApiInterfaceDelegate, TencentSessionDelegate> {
    TencentOAuth* _qqapi;
}

@end


@implementation RCTQQAPI

@synthesize bridge = _bridge;

RCT_EXPORT_MODULE();

- (dispatch_queue_t)methodQueue
{
    return dispatch_get_main_queue();
}

- (NSArray<NSString *> *)supportedEvents
{
    return @[@"QQ_Resp"];
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURL:) name:@"RCTOpenURLNotification" object:nil];
        [self _autoRegisterAPI];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)handleOpenURL:(NSNotification *)note
{
    NSDictionary *userInfo = note.userInfo;
    NSString *url = userInfo[@"url"];
    if ([TencentOAuth HandleOpenURL:[NSURL URLWithString:url]]) {
    }
    else {
        [QQApiInterface handleOpenURL:[NSURL URLWithString:url] delegate:self];
    }
}

RCT_EXPORT_METHOD(isQQInstalled:(RCTResponseSenderBlock)callback)
{
    callback(@[[NSNull null], @([QQApiInterface isQQInstalled])]);
}

RCT_EXPORT_METHOD(isQQSupportApi:(RCTResponseSenderBlock)callback)
{
    callback(@[[NSNull null], @([QQApiInterface isQQSupportApi])]);
}

RCT_EXPORT_METHOD(login:(NSString *)scopes
                  :(RCTResponseSenderBlock)callback)
{
    NSArray *scopeArray = nil;
    if (scopes && scopes.length) {
        scopeArray = [scopes componentsSeparatedByString:@","];
    }
    if (scopeArray == nil) {
        scopeArray = @[@"get_user_info", @"get_simple_userinfo"];
    }
    BOOL success = [_qqapi authorize:scopeArray];
    callback(@[success ? [NSNull null] : INVOKE_FAILED]);
}

RCT_EXPORT_METHOD(shareToQQ:(NSDictionary *)data
                  :(RCTResponseSenderBlock)callback)
{
    [self _shareToQQWithData:data scene:0 callBack:callback];
}

RCT_EXPORT_METHOD(shareToQzone:(NSDictionary *)data
                  :(RCTResponseSenderBlock)callback)
{
    [self _shareToQQWithData:data scene:1 callBack:callback];
}

RCT_EXPORT_METHOD(logout)
{
    [_qqapi logout:nil];
}

- (void)_shareToQQWithData:(NSDictionary *)aData scene:(int)aScene callBack:(RCTResponseSenderBlock)callback {
    NSString *imageUrl = aData[RCTQQShareImageUrl];
    if (imageUrl.length && _bridge.imageLoader) {
        CGSize size = CGSizeZero;
        if (![aData[RCTQQShareType] isEqualToString:RCTQQShareTypeImage]) {
            CGFloat thumbImageSize = 80;
            size = CGSizeMake(thumbImageSize,thumbImageSize);
        }
        [_bridge.imageLoader loadImageWithURLRequest:[RCTConvert NSURLRequest:imageUrl] callback:^(NSError *error, UIImage *image) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self _shareToQQWithData:aData image:image scene:aScene callBack:callback];
            });
        }];
    }
    else {
        [self _shareToQQWithData:aData image:nil scene:aScene callBack:callback];
    }
}


- (void)_shareToQQWithData:(NSDictionary *)aData image:(UIImage*) image scene:(int)aScene callBack:(RCTResponseSenderBlock)callback {
    NSString *type = aData[RCTQQShareType];

    NSString *title = aData[RCTQQShareTitle];

    NSString *description= aData[RCTQQShareDescription];
    NSString *imgPath = aData[RCTQQShareImageUrl];
    NSString *webpageUrl = aData[RCTQQShareWebpageUrl]? :@"";
    NSString *flashUrl = aData[@"flashUrl"];

    QQApiObject *message = nil;

    if (type.length <=0 || [type isEqualToString: RCTQQShareTypeNews]) {
        message = [QQApiNewsObject
                   objectWithURL:[NSURL URLWithString:webpageUrl]
                   title:title
                   description:description
                   previewImageURL:[NSURL URLWithString:imgPath]];
    }
    else if ([type isEqualToString: RCTQQShareTypeText]) {
        message = [QQApiTextObject objectWithText:description];
    }
    else if ([type isEqualToString: RCTQQShareTypeImage]) {
        NSData *imgData = UIImageJPEGRepresentation(image, 1);
        message = [QQApiImageObject objectWithData:imgData
                                  previewImageData:imgData
                                             title:title
                                       description:description];
    }
    else if ([type isEqualToString: RCTQQShareTypeAudio]) {
        QQApiAudioObject *audioObj = [QQApiAudioObject objectWithURL:[NSURL URLWithString:webpageUrl]
                                                               title:title
                                                         description:description
                                                     previewImageURL:[NSURL URLWithString:imgPath]];
        if (flashUrl) {
            [audioObj setFlashURL:[NSURL URLWithString:flashUrl]];
        }
        message = audioObj;
    }
    else if ([type isEqualToString: RCTQQShareTypeVideo]) {
        QQApiVideoObject *videoObj = [QQApiVideoObject objectWithURL:[NSURL URLWithString:webpageUrl]
                                                               title:title
                                                         description:description
                                                     previewImageURL:[NSURL URLWithString:imgPath]];
        if (flashUrl) {
            [videoObj setFlashURL:[NSURL URLWithString:flashUrl]];
        }
        message = videoObj;
    }

    QQApiSendResultCode sent = EQQAPISENDFAILD;

    if (message != nil) {
        SendMessageToQQReq *req = [SendMessageToQQReq reqWithContent:message];
        if (aScene == 0) {
            sent = [QQApiInterface sendReq:req];
        }
        else {
            sent = [QQApiInterface SendReqToQZone:req];
        }
    }

    if (sent == EQQAPISENDSUCESS) {
        callback(@[[NSNull null]]);
    }
    else if (sent == EQQAPIAPPSHAREASYNC) {
        callback(@[[NSNull null]]);
    }
    else {
        callback(INVOKE_FAILED);
    }
}


- (void)_autoRegisterAPI
{
    NSString *appId = nil;
    NSArray *list = [[[NSBundle mainBundle] infoDictionary] valueForKey:@"CFBundleURLTypes"];
    for (NSDictionary *item in list) {
        NSString *name = item[@"CFBundleURLName"];
        if ([name isEqualToString:@"qq"]) {
            NSArray *schemes = item[@"CFBundleURLSchemes"];
            if (schemes.count > 0)
            {
                appId = [schemes[0] substringFromIndex:@"tencent".length];
                break;
            }
        }
    }
    _qqapi = [[TencentOAuth alloc] initWithAppId:appId andDelegate:self];

}

#pragma mark - qq delegate
- (void)onReq:(QQBaseReq *)req
{
    
}

- (void)onResp:(QQBaseResp *)resp
{
    if ([resp isKindOfClass:[SendMessageToQQResp class]]) {
        
    }
    NSMutableDictionary *body = @{@"type":@"QQShareResponse"}.mutableCopy;
    body[@"errMsg"] = resp.errorDescription;
    if (resp.errorDescription) {
        body[@"errCode"] = @(-1);
    }
    else {
        body[@"errCode"] = @(0);
    }
    body[@"result"] =resp.result;
    body[@"extendInfo"] =resp.extendInfo;
    
    [self sendEventWithName:@"QQ_Resp" body:body];
}

- (void)isOnlineResponse:(NSDictionary *)response
{
    
}

#pragma mark - oauth delegate
- (void)tencentDidLogin
{
    NSMutableDictionary *body = @{@"type":@"QQAuthorizeResponse"}.mutableCopy;
    body[@"errCode"] = @(0);
    body[@"openid"] = _qqapi.openId;
    body[@"access_token"] = _qqapi.accessToken;
    body[@"expires_in"] = @([_qqapi.expirationDate timeIntervalSince1970]*1000);
    body[@"oauth_consumer_key"] =_qqapi.appId;

    [self sendEventWithName:@"QQ_Resp" body:body];
}

- (void)tencentDidNotLogin:(BOOL)cancelled
{
    NSMutableDictionary *body = @{@"type":@"QQAuthorizeResponse"}.mutableCopy;
    body[@"errCode"] = @(-1);
    if (cancelled) {
        body[@"errMsg"] = @"login canceled";
    }
    else {
        body[@"errMsg"] = @"login failed";
    }
    [self sendEventWithName:@"QQ_Resp" body:body];
    
}

- (void)tencentDidNotNetWork
{
}

@end

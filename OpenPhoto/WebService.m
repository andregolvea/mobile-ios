//
//  WebService.m
//  OpenPhoto
//
//  Created by Patrick Santana on 03/08/11.
//  Copyright 2011 OpenPhoto. All rights reserved.
//

#import "WebService.h"

// Private interface definition
@interface WebService() 
- (void)sendRequest:(NSString*) request;
- (BOOL) validateNetwork;
@end

@implementation WebService
@synthesize delegate;
@synthesize internetActive, hostActive;


- (id)init {
    self = [super init];
    if (self) {
        
        // check for internet connection
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(checkNetworkStatus:) name:kReachabilityChangedNotification object:nil];
        
        internetReachable = [[Reachability reachabilityForInternetConnection] retain];
        [internetReachable startNotifier];
        
        // check if a pathway to a random host exists
        hostReachable = [[Reachability reachabilityWithHostName: @"www.openphoto.me"] retain];
        [hostReachable startNotifier];
        
        self.internetActive = NO;
        self.hostActive = NO;
    }
    return self;
}
- (void) getTags{
    [self sendRequest:@"/tags/list.json"];
}

- (void) getHomePictures{
    NSMutableString *homePicturesRequest = [NSMutableString stringWithFormat: @"%@",@"/photos/list.json?sortBy=dateUploaded,DESC&pageSize=4&returnSizes="];
    
    if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)] == YES && [[UIScreen mainScreen] scale] == 2.00) {
        // retina display
        [homePicturesRequest appendString:@"640x770xCR"];
    }else{
        // not retina display
        [homePicturesRequest appendString:@"320x385xCR"];
    }
    
    [self sendRequest:homePicturesRequest];
}

- (void) loadGallery:(int) pageSize{
    NSMutableString *loadGalleryRequest = [NSMutableString stringWithFormat: @"%@%@%@", 
                                           @"/photos/list.json?pageSize=", 
                                           [NSString stringWithFormat:@"%d", pageSize],
                                           @"&returnSizes=200x200,640x960"];
     [self sendRequest:loadGalleryRequest];
}

-(void) loadGallery:(int) pageSize withTag:(NSString*) tag{
    NSMutableString *loadGalleryRequest = [NSMutableString stringWithFormat: @"%@%@%@%@%@", 
                                           @"/photos/list.json?pageSize=", 
                                           [NSString stringWithFormat:@"%d", pageSize],
                                           @"&returnSizes=200x200,640x960",
                                           @"&tags=",tag];
    [self sendRequest:loadGalleryRequest];
}

-(NSURL*) getOAuthInitialUrl{
    // get the url
    NSString* server = [[NSUserDefaults standardUserDefaults] valueForKey:kOpenPhotoServer];
    NSString* url = [[[NSString alloc]initWithFormat:@"%@%@",server,@"/v1/oauth/authorize?oauth_callback=openphoto://"] autorelease];
    
    NSLog(@"URL for OAuth initialization = %@",url);
    return [NSURL URLWithString:url];
}

-(NSURL*) getOAuthAccessUrl{
    // get the url
    NSString* server = [[NSUserDefaults standardUserDefaults] valueForKey:kOpenPhotoServer];
    NSString* url = [[[NSString alloc]initWithFormat:@"%@%@",server,@"/v1/oauth/token/access"] autorelease];
    
    NSLog(@"URL for OAuth Access = %@",url);
    return [NSURL URLWithString:url];  
}

-(NSURL*) getOAuthTestUrl{
    // get the url
    NSString* server = [[NSUserDefaults standardUserDefaults] valueForKey:kOpenPhotoServer];
    NSString* url = [[[NSString alloc]initWithFormat:@"%@%@",server,@"/v1/oauth/test"] autorelease];
    
    NSLog(@"URL for OAuth Test = %@",url);
    return [NSURL URLWithString:url];  
}

-(void) sendTestRequest{
    [self sendRequest:@"/hello.json?auth=1"];
}

-(void) uploadPicture:(NSDictionary*) values{
    if ([self validateNetwork] == NO){
        [self.delegate notifyUserNoInternet];
    }else{
        // send message to the site. it is pickedImage
        NSData *imageData = UIImageJPEGRepresentation([values objectForKey:@"image"] ,0.7);
        //Custom implementations, no built in base64 or HTTP escaping for iPhone
        NSString *imageB64   = [QSStrings encodeBase64WithData:imageData]; 
        NSString* imageEscaped = [Base64Utilities fullEscape:imageB64];
        
        
        // set all details to send
        NSString *uploadCall = [NSString stringWithFormat:@"photo=%@&title=%@&description=%@&permission=%@&exifCameraMake=%@&exifCameraModel=%@&tags=%@",imageEscaped,[values objectForKey:@"title"],[values objectForKey:@"description"],[values objectForKey:@"permission"],[values objectForKey:@"exifCameraMake"],[values objectForKey:@"exifCameraModel"], [values objectForKey:@"tags"]];
        
        NSMutableString *urlString =     [NSMutableString stringWithFormat: @"%@/photo/upload.json", 
                                          [[NSUserDefaults standardUserDefaults] stringForKey:kOpenPhotoServer]];
        
        NSLog(@"Request to be sent = [%@]",urlString);
        
        // transform in URL for the request
        NSURL *url = [NSURL URLWithString:urlString];
        
        NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
        
        // token to send. We get the details from the user defaults
        OAToken *token = [[OAToken alloc] initWithKey:[standardUserDefaults valueForKey:kAuthenticationOAuthToken] 
                                               secret:[standardUserDefaults valueForKey:kAuthenticationOAuthSecret]];
        
        // consumer to send. We get the details from the user defaults
        OAConsumer *consumer = [[OAConsumer alloc] initWithKey:[standardUserDefaults valueForKey:kAuthenticationConsumerKey] 
                                                        secret:[standardUserDefaults valueForKey:kAuthenticationConsumerSecret] ];
        
        
        OAMutableURLRequest *oaUrlRequest = [[OAMutableURLRequest alloc] initWithURL:url
                                                                            consumer:consumer
                                                                               token:token
                                                                               realm:nil
                                                                   signatureProvider:nil];
        [oaUrlRequest setHTTPMethod:@"POST"];   
        [oaUrlRequest setValue:[NSString stringWithFormat:@"%d",[uploadCall length]] forHTTPHeaderField:@"Content-length"];
        
        // prepare the Authentication Header
        [oaUrlRequest prepare];
        [oaUrlRequest setHTTPBody:[uploadCall dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO]];
        
        
        
        // send the request
        OADataFetcher *fetcher = [[OADataFetcher alloc] init];
        [fetcher fetchDataWithRequest:oaUrlRequest
                             delegate:self
                    didFinishSelector:@selector(requestTicket:didFinishWithData:)
                      didFailSelector:@selector(requestTicket:didFailWithError:)];
    }
    
}

- (void) checkNetworkStatus:(NSNotification *)notice
{
    // called after network status changes
    NetworkStatus internetStatus = [internetReachable currentReachabilityStatus];
    switch (internetStatus)
    
    {
        case NotReachable:
        {
            self.internetActive = NO; 
            break;
        }
        case ReachableViaWiFi:
        {
            self.internetActive = YES;
            break;
        }
        case ReachableViaWWAN:
        {
            self.internetActive = YES;
            break;
        }
    }
    
    
    NetworkStatus hostStatus = [hostReachable currentReachabilityStatus];
    switch (hostStatus)  
    {
        case NotReachable:
        {
            self.hostActive = NO;
            break;
        }
        case ReachableViaWiFi:
        {
            self.hostActive = YES;
            break;
        }
        case ReachableViaWWAN:
        {
            self.hostActive = YES;
            break;
        }
    }
}


///////////////////////////////////
// PRIVATES METHODS
//////////////////////////////////
- (void)sendRequest:(NSString*) request{
    if ([self validateNetwork] == NO){
        [self.delegate notifyUserNoInternet];
    }else{
        
        // create the url to connect to OpenPhoto
        NSMutableString *urlString =     [NSMutableString stringWithFormat: @"%@%@", 
                                          [[NSUserDefaults standardUserDefaults] stringForKey:kOpenPhotoServer], request];
        
        NSLog(@"Request to be sent = [%@]",urlString);
        
        // transform in URL for the request
        NSURL *url = [NSURL URLWithString:urlString];
        
        NSUserDefaults *standardUserDefaults = [NSUserDefaults standardUserDefaults];
        
        // token to send. We get the details from the user defaults
        OAToken *token = [[OAToken alloc] initWithKey:[standardUserDefaults valueForKey:kAuthenticationOAuthToken] 
                                               secret:[standardUserDefaults valueForKey:kAuthenticationOAuthSecret]];
        
        // consumer to send. We get the details from the user defaults
        OAConsumer *consumer = [[OAConsumer alloc] initWithKey:[standardUserDefaults valueForKey:kAuthenticationConsumerKey] 
                                                        secret:[standardUserDefaults valueForKey:kAuthenticationConsumerSecret] ];
        
        
        OAMutableURLRequest *oaUrlRequest = [[OAMutableURLRequest alloc] initWithURL:url
                                                                            consumer:consumer
                                                                               token:token
                                                                               realm:nil
                                                                   signatureProvider:nil];
        [oaUrlRequest setHTTPMethod:@"GET"];
        
        // prepare the Authentication Header
        [oaUrlRequest prepare];
        
        // send the request
        OADataFetcher *fetcher = [[OADataFetcher alloc] init];
        [fetcher fetchDataWithRequest:oaUrlRequest
                             delegate:self
                    didFinishSelector:@selector(requestTicket:didFinishWithData:)
                      didFailSelector:@selector(requestTicket:didFailWithError:)];
    }
}

- (void)requestTicket:(OAServiceTicket *)ticket didFinishWithData:(NSData *)data{
    if (ticket.didSucceed) {
        NSString *jsonString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSLog(@"Succeed = %@",jsonString);        
        
        // Create a dictionary from JSON string
        // When there are newline characters in the JSON string, 
        // the error "Unescaped control character '0x9'" will be thrown. This removes those characters.
        jsonString =  [jsonString stringByTrimmingCharactersInSet:[NSCharacterSet newlineCharacterSet]];
        NSDictionary *results =  [jsonString JSONValue];
        
        // send the result to the delegate
        [self.delegate receivedResponse:results];
    }else{
        NSLog(@"The request didn't succeed=%@",[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
    }
}
- (void)requestTicket:(OAServiceTicket *)ticket didFailWithError:(NSError *)error{
    NSLog(@"Error to send request = %@; error code=%@", [error userInfo],[error code]);
}


- (BOOL) validateNetwork{
    // check for the network and if our server is reachable
//    if (self.internetActive == NO || self.hostActive == NO){
//        return NO;
//    }
    
    return YES;
}


- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [internetReachable release];
    [hostReachable release];
    [super dealloc];
}

@end

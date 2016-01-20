#import "Downloader.h"

@implementation DownloadParams

@end

@interface Downloader()

@property (copy) DownloadParams* params;

@property (retain) NSURLConnection* connection;
@property (retain) NSNumber* statusCode;
@property (retain) NSNumber* contentLength;
@property (retain) NSNumber* bytesWritten;

@property (retain) NSFileHandle* fileHandle;

@end

@implementation Downloader

- (void)downloadFile:(DownloadParams*)params
{
  _params = params;
  
  _bytesWritten = 0;

  NSURL* url = [NSURL URLWithString:_params.fromUrl];

  NSMutableURLRequest* downloadRequest = [NSMutableURLRequest requestWithURL:url
                                                                 cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                             timeoutInterval:30];

  _connection = [[NSURLConnection alloc] initWithRequest:downloadRequest delegate:self startImmediately:NO];

  [_connection scheduleInRunLoop:[NSRunLoop mainRunLoop] forMode:NSDefaultRunLoopMode];

  [_connection start];
}

- (void)connection:(NSURLConnection*)connection didFailWithError:(NSError*)error
{
  [_fileHandle closeFile];
  
  NSString *tempPath = [_params.toFile stringByAppendingPathExtension:@"tmp"];
  
  NSError *err = nil;
  if ([[NSFileManager defaultManager] fileExistsAtPath:tempPath isDirectory:false]) {
    [[NSFileManager defaultManager] removeItemAtPath:tempPath error:&err];
  }

  return _params.errorCallback(error);
}

- (void)connection:(NSURLConnection*)connection didReceiveResponse:(NSURLResponse*)response
{
  NSString *tempPath = [_params.toFile stringByAppendingPathExtension:@"tmp"];
    
  [[NSFileManager defaultManager] createFileAtPath:tempPath contents:nil attributes:nil];
  [[NSURL URLWithString:tempPath] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];

  _fileHandle = [NSFileHandle fileHandleForWritingAtPath:tempPath];

  if (!_fileHandle) {
    NSError* error = [NSError errorWithDomain:@"Downloader" code:NSURLErrorFileDoesNotExist userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat: @"Failed to create  target file at path: %@", tempPath]}];
    
    if (_params.errorCallback) {
      return _params.errorCallback(error);
    }
  }
    
  NSHTTPURLResponse* httpUrlResponse = (NSHTTPURLResponse*)response;

  _statusCode = [NSNumber numberWithLong:httpUrlResponse.statusCode];
  _contentLength = [NSNumber numberWithLongLong: httpUrlResponse.expectedContentLength];
  
  return _params.beginCallback(_statusCode, _contentLength, httpUrlResponse.allHeaderFields);
}

- (void)connection:(NSURLConnection*)connection didReceiveData:(NSData*)data
{
  if ([_statusCode isEqualToNumber:[NSNumber numberWithInt:200]]) {
    [_fileHandle writeData:data];

    _bytesWritten = [NSNumber numberWithUnsignedInteger:[_bytesWritten unsignedIntegerValue] + data.length];

    return _params.progressCallback(_contentLength, _bytesWritten);
  }
}

- (void)connectionDidFinishLoading:(NSURLConnection*)connection
{
  [_fileHandle closeFile];
  
  NSString *tempPath = [_params.toFile stringByAppendingPathExtension:@"tmp"];
  
  NSError *error = nil;
  if ([[NSFileManager defaultManager] fileExistsAtPath:_params.toFile isDirectory:false]) {
    [[NSFileManager defaultManager] removeItemAtPath:_params.toFile error:&error];
  }
  [[NSFileManager defaultManager] moveItemAtPath:tempPath toPath:_params.toFile error:&error];
  [[NSURL URLWithString:_params.toFile] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
  
  NSDictionary *fileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:_params.toFile error:&error];
  
  return _params.callback(_statusCode, [fileAttributes valueForKey:@"NSFileSize"]);
}

- (void)stopDownload
{
  [_connection cancel];
}

@end

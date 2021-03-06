#import "FileItem.h"
#import "FSEventsManager.h"
#import "SCMManager.h"

// =======================================
// = File system and SCM status observer =
// =======================================

@interface FileSystemObserver : NSObject
{
	void(^_handler)(NSArray<NSURL*>*);

	NSArray<NSURL*>* _fsEventsURLs;
	NSArray<NSURL*>* _scmURLs;

	id _fsEventsObserver;
	id _scmObserver;
}
@end

@implementation FileSystemObserver
- (instancetype)initWithURL:(NSURL*)url usingBlock:(void(^)(NSArray<NSURL*>*))handler
{
	if(self = [super init])
	{
		_handler = handler;
		_scmURLs = @[ ];

		__weak FileSystemObserver* weakSelf = self;
		_fsEventsObserver = [FSEventsManager.sharedInstance addObserverToDirectoryAtURL:url usingBlock:^(NSArray<NSURL*>* urls){
			[weakSelf updateFSEventsURLs:urls scmURLs:nil];
		}];

		_scmObserver = [SCMManager.sharedInstance addObserverForStatus:scm::status::deleted inDirectoryAtURL:url usingBlock:^(std::map<std::string, scm::status::type> const&){
			[weakSelf updateFSEventsURLs:nil scmURLs:[SCMManager.sharedInstance urlsWithStatus:scm::status::deleted inDirectoryAtURL:url]];
		}];
	}
	return self;
}

- (void)dealloc
{
	[FSEventsManager.sharedInstance removeObserver:_fsEventsObserver];
	[SCMManager.sharedInstance removeObserver:_scmObserver];
}

- (void)updateFSEventsURLs:(NSArray<NSURL*>*)fsEventsURLs scmURLs:(NSArray<NSURL*>*)scmURLs
{
	_fsEventsURLs = fsEventsURLs ?: _fsEventsURLs;
	_scmURLs      = scmURLs      ?: _scmURLs;

	if(!_fsEventsURLs)
		return;

	NSMutableSet* set = [NSMutableSet setWithArray:_fsEventsURLs];
	[set addObjectsFromArray:_scmURLs];

	_handler(set.allObjects);
}
@end

// ===================================================
// = Helper classes to manage abstract URL observers =
// ===================================================

@class URLObserver;

@interface URLObserverClient : NSObject
@property (nonatomic, readonly) void(^handler)(NSArray<NSURL*>*);
@property (nonatomic) URLObserver* URLObserver;
- (instancetype)initWithBlock:(void(^)(NSArray<NSURL*>*))handler;
- (void)removeFromURLObserver;
@end

@interface URLObserver : NSObject
@property (nonatomic, readonly) NSURL* URL;
@property (nonatomic, readonly) NSMutableArray<URLObserverClient*>* clients;
@property (nonatomic) id driver;
@property (nonatomic) NSArray<NSURL*>* cachedURLs;
- (void)addClient:(URLObserverClient*)client;
- (void)removeClient:(URLObserverClient*)client;
@end

@implementation URLObserver
- (instancetype)initWithURL:(NSURL*)url
{
	if(self = [super init])
	{
		_URL     = url;
		_clients = [NSMutableArray array];
	}
	return self;
}

- (void)setCachedURLs:(NSArray<NSURL*>*)urls
{
	_cachedURLs = urls;
	for(URLObserverClient* client in [_clients copy])
		client.handler(urls);
}

- (void)addClient:(URLObserverClient*)client
{
	client.URLObserver = self;
	[_clients addObject:client];
	if(_cachedURLs && _cachedURLs.count)
		client.handler(_cachedURLs);
}

- (void)removeClient:(URLObserverClient*)client
{
	[_clients removeObject:client];
	client.URLObserver = nil;
}
@end

@implementation URLObserverClient
- (instancetype)initWithBlock:(void(^)(NSArray<NSURL*>*))handler
{
	if(self = [super init])
	{
		_handler = handler;
	}
	return self;
}

- (void)removeFromURLObserver
{
	[_URLObserver removeClient:self];
}
@end

// ==============================
// = FileItem observer category =
// ==============================

@implementation FileItem (Observer)
+ (URLObserverClient*)addObserverToDirectoryAtURL:(NSURL*)url usingBlock:(void(^)(NSArray<NSURL*>*))handler
{
	static NSMapTable<NSURL*, URLObserver*>* observers = [NSMapTable strongToWeakObjectsMapTable];

	URLObserver* observer = [observers objectForKey:url];
	if(!observer)
	{
		observer = [[URLObserver alloc] initWithURL:url];
		[observers setObject:observer forKey:url];
	}

	URLObserverClient* client = [[URLObserverClient alloc] initWithBlock:handler];
	[observer addClient:client];

	if(!observer.driver)
	{
		__weak URLObserver* weakObserver = observer;
		observer.driver = [[self classForURL:url] makeObserverForURL:url usingBlock:^(NSArray<NSURL*>* urls){
			weakObserver.cachedURLs = urls;
		}];
	}

	return client;
}

+ (void)removeObserver:(URLObserverClient*)someObserver
{
	[someObserver removeFromURLObserver];
}

+ (id)makeObserverForURL:(NSURL*)url usingBlock:(void(^)(NSArray<NSURL*>*))handler
{
	return url.isFileURL ? [[FileSystemObserver alloc] initWithURL:url usingBlock:handler] : nil;
}
@end

//----------------------------------------------------------------------------------------
//	MyWorkingCopy.m - Working Copy model
//
//	Copyright 2004 - 2007 Dominique Peretti.
//	Copyright © Chris, 2007 - 2010.  All rights reserved.
//----------------------------------------------------------------------------------------

#import "MyWorkingCopy.h"
#import "MyWorkingCopyController.h"
#import "MyApp.h"
#import "MySVN.h"
#import "Tasks.h"
#import "NSString+MyAdditions.h"
#import "CommonUtils.h"
#import "IconUtils.h"
#import "ReviewCommit.h"
#import "SvnInterface.h"
#import <unistd.h>


ConstString	kUseOldParsingMethod = @"useOldParsingMethod";
ConstString	keyShowExternals     = @"showWCExternals",
			keySmartMode         = @"smartMode",
			keyFlatMode          = @"flatMode";
static ConstString kCurrentDir = @".";
static BOOL gShowExternals = FALSE;


//----------------------------------------------------------------------------------------

static BOOL
useOldParsingMethod ()
{
	return GetPreferenceBool(kUseOldParsingMethod);
}


//----------------------------------------------------------------------------------------
#pragma mark -
//----------------------------------------------------------------------------------------

@interface MyWorkingCopy (Private)

	- (void) computesNewVerboseResultArray: (NSData*) xmlData;
	- (void) setDisplayedTaskObj: (NSMutableDictionary*) aDisplayedTaskObj;
	- (void) setSvnDirectories:   (WCTreeEntry*)         aSvnDirectories;

@end	// MyWorkingCopy (Private)


//----------------------------------------------------------------------------------------

@implementation MyWorkingCopy


//----------------------------------------------------------------------------------------

- (void) svnError: (TaskObj*) taskObj
{
	NSString* errMsg = stdErr(taskObj);
	if (errMsg)
		[controller svnError: errMsg];
}


//----------------------------------------------------------------------------------------

- (void) svnRefresh
{
//	dprintf("isVisible=%d", [[controller window] isVisible]);
	if (useOldParsingMethod())
		[controller fetchSvnInfo];
	[controller fetchSvnStatus];
}


//----------------------------------------------------------------------------------------
#pragma mark -
//----------------------------------------------------------------------------------------

+ (void) presetDocumentName: name
{
	[MyWorkingCopyController presetDocumentName: name];
}


//----------------------------------------------------------------------------------------

- (id) init
{
	if (self = [super init])
	{
		flatMode   =
		smartMode  = TRUE;
		filterMode = kFilterAll;

		[self setOutlineSelectedPath: @""];
		// initialize svnFiles:
		// svnFilesAC is bound in Interface Builder to this variable.
		[self setSvnFiles: [NSArray array]];
		svnDirectories = [WCTreeEntry alloc];

		// register self as an observer for bound variables
		[self addObserver: self forKeyPath: keySmartMode options: 0 context: NULL];
		[self addObserver: self forKeyPath: keyFlatMode  options: 0 context: NULL];
		gShowExternals = GetPreferenceBool(keyShowExternals);
		[Preferences() addObserver: self forKeyPath: keyShowExternals options: 0 context: NULL];
	}

	return self;
}


//----------------------------------------------------------------------------------------

- (void) setup: (NSString*) title
		 user:  (NSString*) username
		 pass:  (NSString*) password
		 path:  (NSString*) fullPath
{
	[self setFileURL: [NSURL fileURLWithPath: fullPath]];
	[self setWindowTitle:     title];
	[self setUser:            username];
	[self setPass:            password];
	[self setWorkingCopyPath: fullPath];
}


//----------------------------------------------------------------------------------------

- (void) dealloc
{
//	dprintf("%@", self);
	[self setUser: nil];
	[self setPass: nil];
	[self setRevision: nil];
	[self setWorkingCopyPath: nil];
	[self setWindowTitle: nil];
	[self setSvnFiles: nil];
	[self setSvnDirectories: nil];
	[outlineSelectedPath release];
	[self setRepositoryUrl: nil];
	[self setDisplayedTaskObj: nil];
	[subControllers release];
	SvnEndClient(fSvnEnv);

	[super dealloc];
}


//----------------------------------------------------------------------------------------

- (NSString*) windowNibName
{
	return @"MyWorkingCopy";
}


//----------------------------------------------------------------------------------------

- (void) registerSubController: (id) aController
{
	if (subControllers == nil)
		subControllers = [NSMutableSet new];
	[subControllers addObject: aController];
}


//----------------------------------------------------------------------------------------

- (void) unregisterSubController: (id) aController
{
	Assert(subControllers != nil);
	Assert([subControllers containsObject: aController]);
	[subControllers removeObject: aController];
}


//----------------------------------------------------------------------------------------

- (id) anySubController
{
	return [subControllers anyObject];
}


//----------------------------------------------------------------------------------------

- (int) countUnsavedSubControllers
{
	int count = 0;
	for_each_obj(en, it, subControllers)
	{
		if ([it isDocumentEdited])
			++count;
	}
	return count;
}


//----------------------------------------------------------------------------------------

- (void) refreshSubController
{
	for_each_obj(en, it, subControllers)
		[it buildFileList];
}


//----------------------------------------------------------------------------------------

- (void) close
{
	// tell the task center to cancel pending callbacks to prevent crash
	[Tasks cancelCallbacksOnTarget: self];

	[self removeObserver: self forKeyPath: keySmartMode];
	[self removeObserver: self forKeyPath: keyFlatMode];

	controller = nil;
	[super close];
}


//----------------------------------------------------------------------------------------

- (NSInvocation*) genericCompletedCallback
{
	return MakeCallbackInvocation(self, @selector(svnGenericCompletedCallback:));
}


//----------------------------------------------------------------------------------------

- (NSDictionary*) documentNameDict
{
	return [NSDictionary dictionaryWithObject: windowTitle ? windowTitle : @"" forKey: @"documentName"];
}


//----------------------------------------------------------------------------------------
#pragma mark	-
#pragma mark	svn status
//----------------------------------------------------------------------------------------
/*
	Working Copy Item = {
		col1:				<char>									(NSString)
		col2:				<char>									(NSString)
		col3:				<char>									(NSString)
		col4:				<char>									(NSString)
		col5:				<char>									(NSString)
		col6:				<char>									(NSString)
		col7:				<char>									(NSString)
		col8:				<char>									(NSString)
		dirPath:             "dir-in-wc/"							(NSString)
		displayPath:         "file-name" or "dir-in-wc/file-name"	(NSString)
		fullPath:            "/Users/.../file-name"					(NSString)
		icon:                <16x16-image>							(NSImage)
		path:                "dir-in-wc/file-name"					(NSString)
		revisionCurrent:     <revision-number>						(NSString)
		revisionLastChanged: <revision-number>						(NSString)
		user:                <author>								(NSString)

		modified:				(NSBool)
		new:					(NSBool)
		missing:				(NSBool)
		added:					(NSBool)
		deleted:				(NSBool)

		renamable:				(NSBool)
		addable:				(NSBool)
		removable:				(NSBool)
		updatable:				(NSBool)
		revertible:				(NSBool)
		committable:			(NSBool)
		resolvable:				(NSBool)
		lockable:				(NSBool)
		unlockable:				(NSBool)
	}
*/

struct SvnStatusEnv
{
	MyWorkingCopy*			fInterface;
	NSMutableDictionary*	fTree;
	NSMutableArray*			newSvnFiles;
	NSFileManager*			fileManager;
	int						wcPathLength;
	BOOL					flatMode, showUpdates;
};

typedef struct SvnStatusEnv SvnStatusEnv;


//----------------------------------------------------------------------------------------

static NSMutableArray*
addDirToTree (const SvnStatusEnv* env, ConstString fullPath)
{
//	dprintf("('%@')", fullPath);
	NSMutableArray* children = [env->fTree objectForKey: fullPath];
	if (children == nil)
	{
		ConstString parent = [fullPath stringByDeletingLastPathComponent];
		int parentLen = [parent length];
		ConstString name = [fullPath substringFromIndex: parentLen + 1];
		children = [NSMutableArray array];
		[env->fTree setObject: children forKey: fullPath];
		id entry = [WCTreeEntry create: children
								  name: name
								  path: [fullPath substringFromIndex: env->wcPathLength + 1]];
		[addDirToTree(env, parent) addObject: entry];
		[entry release];
	}
	return children;
}


//----------------------------------------------------------------------------------------

static inline BOOL
isOutOfDate (SvnWCStatusKind repos_status, SvnWCStatusKind status)
{
	return repos_status > svn_wc_status_none && repos_status != status;
}


//----------------------------------------------------------------------------------------
// WC 'svn status' callback.

static void
svnStatusReceiver (void*     baton,
				   ConstCStr path,
				   SvnStatus status)
{
//	dprintf("('%s')", path);
	const SvnStatusEnv* const env = (const SvnStatusEnv*) baton;
	const svn_wc_entry_t* const entry = status->entry;

	ConstString itemFullPath = UTF8(path);
	ConstString itemPath = (env->wcPathLength < [itemFullPath length])
								? [itemFullPath substringFromIndex: env->wcPathLength + 1] : kCurrentDir;

	const SvnWCStatusKind text_status = status->text_status,
						  prop_status = status->prop_status;
	// see all meanings at http://svnbook.red-bean.com/nightly/en/svn.ref.svn.c.status.html
	// COLUMN 1
	ConstString column1 = SvnStatusToString(text_status);

	// COLUMN 2
	ConstString column2 = SvnStatusToString(prop_status);

	// COLUMN 3
	ConstString column3 = status->locked ? @"L" : @" ";

	// COLUMN 4
	ConstString column4 = status->copied ? @"+" : @" ";

	// COLUMN 5
	ConstString column5 = status->switched ? @"S" : @" ";

	// COLUMN 6
	// see <http://svn.collab.net/repos/svn/trunk/subversion/svn/status.c>, ~ line 112 for explanation
	ConstString kIsLocked = @"K";
	NSString* column6 = @" ";
	ConstCStr const wc_token = entry ? entry->lock_token : NULL;
	if (env->showUpdates)
	{
		const svn_lock_t* const repos_lock = status->repos_lock;
		ConstCStr const repos_token = repos_lock ? repos_lock->token : NULL;
		if (repos_token)
		{
			if (wc_token)
			{
				column6 = !strcmp(wc_token, repos_token)
							? kIsLocked	// File is locked in this working copy
							: @"T";		// File was locked in this working copy, but the lock has been 'stolen'
										// and is invalid. The file is currently locked in the repository
			}
			else
				column6 = @"O";			// File is locked either by another user or in another working copy
		}
		else if (wc_token)				// File was locked in this working copy, but the lock has
			 column6 = @"B";			// been 'broken' and is invalid. The file is no longer locked
	}
	else if (wc_token)
		column6 = kIsLocked;			// File is locked in this working copy

	// COLUMN 7
	ConstString column7 = (isOutOfDate(status->repos_text_status, text_status) ||
						   isOutOfDate(status->repos_prop_status, prop_status)) ? @"*" : @" ";

	// COLUMN 8
	ConstString column8 = (prop_status == svn_wc_status_normal) ? @"P" : SvnStatusToString(prop_status);

	BOOL renamable = NO, addable = NO, removable = NO, updatable = NO, revertible = NO, committable = NO,
		 copiable = NO, movable = NO, resolvable = NO, lockable = YES, unlockable = NO;

	if (text_status == svn_wc_status_modified || prop_status == svn_wc_status_modified)
	{
		removable = YES;
		updatable = YES;
		revertible = YES;
		committable = YES;
	}
	if (text_status == svn_wc_status_normal)
	{
		removable = YES;
		renamable = YES;
		updatable = YES;
		copiable = YES;
		movable = YES;
	}
	else if (text_status == svn_wc_status_unversioned)
	{
		addable = YES;
		removable = YES;
		lockable = NO;
	}
	else if (text_status == svn_wc_status_missing ||
			 text_status == svn_wc_status_incomplete)
	{
		revertible = YES;
		updatable = YES;
		removable = YES;
		lockable = NO;
	}
	else if (text_status == svn_wc_status_added ||
			 text_status == svn_wc_status_replaced)
	{
		revertible = YES;
		committable = YES;
		lockable = NO;
		updatable = YES;
		removable = YES;
	}
	else if (text_status == svn_wc_status_deleted)
	{
		if ([env->fileManager fileExistsAtPath: itemFullPath])
			addable = YES;
		revertible = YES;
		committable = YES;
		updatable = YES;
	}
	else if (text_status == svn_wc_status_obstructed)
	{
		revertible = YES;
		updatable = YES;
	}
	else if (text_status == svn_wc_status_none)
	{
		updatable = YES;
	}
	if (text_status == svn_wc_status_conflicted || prop_status == svn_wc_status_conflicted)
	{
		revertible = YES;
		resolvable = YES;
	}
	if (column6 == kIsLocked)
	{
		lockable = NO;
		unlockable = YES;
	}

	const BOOL isDirectory = (entry && entry->kind == svn_node_dir);
	if (isDirectory && !env->flatMode && itemPath != kCurrentDir)
		addDirToTree(env, itemFullPath);

	NSString* const revisionCurrent     = entry && !entry->copied ? SvnRevNumToString(entry->revision) : @"";
	NSString* const revisionLastChanged = entry ? SvnRevNumToString(entry->cmt_rev)  : @"";
	NSString* const theUser             = entry ? UTF8(entry->cmt_author)            : @"";
	NSString* const dirPath = [itemPath stringByDeletingLastPathComponent];
	[env->newSvnFiles addObject: [NSDictionary dictionaryWithObjectsAndKeys:
									column1,             @"col1",
									column2,             @"col2",
									column3,             @"col3",
									column4,             @"col4",
									column5,             @"col5",
									column6,             @"col6",
									column7,             @"col7",
									column8,             @"col8",
									revisionCurrent,     @"revisionCurrent",
									revisionLastChanged, @"revisionLastChanged",
									theUser,             @"user",
									(env->flatMode ? itemPath : [itemPath lastPathComponent]),
														 @"displayPath",
									itemPath,            @"path",
									itemFullPath,        @"fullPath",
									dirPath,             @"dirPath",
									NSBool(isDirectory), @"isDir",

									NSBool(text_status == svn_wc_status_modified   ), @"modified",
									NSBool(text_status == svn_wc_status_unversioned), @"new",
									NSBool(text_status == svn_wc_status_missing    ), @"missing",
									NSBool(text_status == svn_wc_status_added      ), @"added",
									NSBool(text_status == svn_wc_status_deleted    ), @"deleted",

									NSBool(renamable  ), @"renamable",
									NSBool(addable    ), @"addable",
									NSBool(removable  ), @"removable",
									NSBool(updatable  ), @"updatable",
									NSBool(revertible ), @"revertible",
									NSBool(committable), @"committable",
									NSBool(resolvable ), @"resolvable",
									NSBool(lockable   ), @"lockable",
									NSBool(unlockable ), @"unlockable",
									nil]];
}


//----------------------------------------------------------------------------------------

struct SvnInfoEnv
{
	MyWorkingCopy*	fInterface;
	char			fURL[2048];
};

typedef struct SvnInfoEnv SvnInfoEnv;


//----------------------------------------------------------------------------------------
// WC 'svn info' callback.  Sets <revision> and <repositoryUrl>.

static SvnError
svnInfoReceiver (void*     baton,
				 ConstCStr path,
				 SvnInfo   info,
				 SvnPool   pool)
{
	#pragma unused(pool)
//	dprintf("URL=<%s>", info->URL);
	SvnInfoEnv* env = (SvnInfoEnv*) baton;
	[env->fInterface svnInfo: info forPath: path];
	strncpy(env->fURL, info->URL, sizeof(env->fURL));

	return SVN_NO_ERROR;
}


//----------------------------------------------------------------------------------------
// svn status of <workingCopyPath> via SvnInterface

- (void) svnDoStatus: (BOOL)    showUpdates_
		 pool:        (SvnPool) pool
{
	SvnClient ctx = SvnSetupClient(&fSvnEnv, self);

	char path[2048];
	if (ToUTF8(workingCopyPath, path, sizeof(path)))
	{
		// Set revision to always be unspecified.
		// Makes svn_client_info retrive WC rev num whereas svn_opt_revision_head retrives HEAD rev num.
		const svn_opt_revision_t rev_opt = { svn_opt_revision_unspecified };

		SvnInfoEnv infoEnv;
		infoEnv.fInterface = self;

		SvnThrowIf(svn_client_info(path, &rev_opt, &rev_opt,
								   svnInfoReceiver, &infoEnv, !kSvnRecurse, ctx, pool));

		SvnStatusEnv env;
		env.fInterface   = self;
		env.newSvnFiles  = [NSMutableArray arrayWithCapacity: 100];
		env.fileManager  = [NSFileManager defaultManager];
		WCTreeEntry* treeDirs = nil;
		if (!flatMode)	// will build folder tree
		{
			id rootChildren = [NSMutableArray array];
			treeDirs = [WCTreeEntry create: rootChildren
									  name: [workingCopyPath lastPathComponent]
									  path: @""];

			env.fTree = [NSMutableDictionary dictionaryWithObject: rootChildren forKey: workingCopyPath];
		}
	//	env.wcPath       = workingCopyPath;
		env.wcPathLength = [workingCopyPath length];
		env.flatMode     = flatMode;
		env.showUpdates  = showUpdates_;

	//	dprintf("('%s')", path);
		svn_revnum_t result_rev = SVN_INVALID_REVNUM;
		SvnThrowIf(svn_client_status2(&result_rev, path, &rev_opt,
									  svnStatusReceiver, &env, kSvnRecurse,
									  ![self smartMode],	// get_all
									  showUpdates_,			// update
									  FALSE,				// no_ignore
									  FALSE,				// ignore_externals
									  ctx, pool));

		if (treeDirs)
			[self setSvnDirectories: treeDirs];
		[controller saveSelection];
		[self setSvnFiles: env.newSvnFiles];
		[controller fetchSvnStatusVerboseReceiveDataFinished];
		[controller restoreSelection];
	//	dprintf("rev=%d url=<%s>", result_rev, env.fURL);
	}
}


//----------------------------------------------------------------------------------------

- (void) fetchSvnStatus: (BOOL) showUpdates_
{
	[controller setStatusMessage: @"Refreshing"];
	if (SvnWantAndHave())
	{
		const id autoPool = [[NSAutoreleasePool alloc] init];
		// Create top-level memory pool.
		SvnPool pool = SvnNewPool();
		@try
		{
			[self svnDoStatus: showUpdates_ pool: pool];
			[self refreshSubController];
		}
		@catch (SvnException* ex)
		{
			SvnReportCatch(ex);
			[controller svnError: [ex message]];
		}
		@finally
		{
			SvnDeletePool(pool);
			[autoPool release];
			[controller setStatusMessage: nil];
		}
	}
	else if (!fStatusPending)
	{
		fStatusPending = TRUE;
		showUpdates = showUpdates_;
		NSString* options[4];
		int count = 0;

		if (![self smartMode])		options[count++] = @"-v";
		if (showUpdates_)			options[count++] = @"-u";
		options[count++] = @"--xml";

		[MySvn statusAtWorkingCopyPath: [self workingCopyPath]
						generalOptions: [self svnOptionsInvocation]
							   options: [NSArray arrayWithObjects: options count: count]
							  callback: MakeCallbackInvocation(self, @selector(svnStatusCompletedCallback:))
						  callbackInfo: nil
							  taskInfo: [self documentNameDict]];
	}
}


//----------------------------------------------------------------------------------------

- (void) fetchSvnStatusVerbose
{
	[self fetchSvnStatus: showUpdates];
}


//----------------------------------------------------------------------------------------

- (void) svnStatusCompletedCallback: (NSMutableDictionary*) taskObj
{
	fStatusPending = FALSE;
	if (isCompleted(taskObj))
	{
		// Save old svnDirectories because fetchSvnStatusVerboseReceiveDataFinished accesses it!
		[controller saveSelection];
		[self computesNewVerboseResultArray: stdOutData(taskObj)];
		[controller setStatusMessage: nil];
		[controller fetchSvnStatusVerboseReceiveDataFinished];
		[controller restoreSelection];
		[self refreshSubController];
	}

	[taskObj removeObjectForKey: @"stdoutData"];
	[self svnError: taskObj];
}


//----------------------------------------------------------------------------------------

- (void) computesNewVerboseResultArray: (NSData*) xmlData
{
	NSError* err = nil;
	NSXMLDocument*
		xmlDoc = [[NSXMLDocument alloc] initWithData: xmlData options: NSXMLNodeOptionsNone error: &err];
	if (xmlDoc == nil)
		xmlDoc = [[NSXMLDocument alloc] initWithData: xmlData options: NSXMLDocumentTidyXML error: &err];

	if (err)
		NSLog(@"Error parsing xml %@", err);

	if (xmlDoc == nil)
		return;

	NSMutableArray* const newSvnFiles = [NSMutableArray arrayWithCapacity: 100];
	const BOOL kFlatMode = [self flatMode];
	NSMutableArray* const rootChildren = kFlatMode ? nil : [NSMutableArray array];
	WCTreeEntry* const outlineDirs =
			 kFlatMode ? nil : [WCTreeEntry create: rootChildren
											  name: [workingCopyPath lastPathComponent]
											  path: @""];

	// <target> node
	NSXMLElement *targetElement = [[[xmlDoc rootElement] elementsForName: @"target"] objectAtIndex: 0];

	// <against revision=""> node
	NSArray *againstElements = [targetElement elementsForName: @"against"];
	if ( [againstElements count] > 0 )
	{
		NSXMLElement *against = [againstElements objectAtIndex: 0];
		[controller setStatusMessage: [NSString stringWithFormat: @"Status against revision: %@",
																  [[against attributeForName: @"revision"] stringValue]]];
	}

	NSString* const targetPath = [[targetElement attributeForName: @"path"] stringValue];
	const int targetPathLength = [targetPath length];
	NSFileManager* const fileManager = [NSFileManager defaultManager];
	const BOOL kShowUpdates = showUpdates;
	NSString* const kCurrentDir = @".";

	NSXMLElement *entry;
	NSEnumerator *e = [[targetElement elementsForName: @"entry"] objectEnumerator];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	// <entry> nodes
	while ( entry = [e nextObject] )
	{
		NSString *revisionCurrent = @"";
		NSString *revisionLastChanged = @"";
		NSString *theUser = @"" ;

		NSXMLElement *wc_status = nil;
		NSString *itemStatus = @"";
		NSString *propStatus = nil;
		NSString* copiedStatus = nil;
		NSString* switchedStatus = nil;

		// wcLockedStatus has nothing to do with lockInWc
		// <http://svnbook.red-bean.com/nightly/en/svn.advanced.locking.html#svn.advanced.locking.meanings>
		NSString* wcLockedStatus = nil;
		NSString* wc_lock = nil;

		// <wc-status> node
		NSArray *wc_status_elements = [entry elementsForName: @"wc-status"];
		if ( [wc_status_elements count] > 0 )
		{
			wc_status = [wc_status_elements objectAtIndex: 0];

			itemStatus = [[wc_status attributeForName: @"item"] stringValue];
			propStatus = [[wc_status attributeForName: @"props"] stringValue];
			copiedStatus = [[wc_status attributeForName: @"copied"] stringValue];
			switchedStatus = [[wc_status attributeForName: @"switched"] stringValue];
			wcLockedStatus = [[wc_status attributeForName: @"wc-locked"] stringValue];

			if ( [wc_status attributeForName: @"revision"] != nil )
			revisionCurrent = [[wc_status attributeForName: @"revision"] stringValue];

			// working copy lock? (when --show-update is NOT used)
			NSArray *lockInWCElements = [wc_status elementsForName: @"lock"];
			if ( [lockInWCElements count] > 0 )
			{
				NSXMLElement *lockInWC = [lockInWCElements objectAtIndex: 0];
				wc_lock = [[[lockInWC elementsForName: @"token"] objectAtIndex: 0] stringValue];
			}

			NSArray *commitElements = [wc_status elementsForName: @"commit"];
			if ( [commitElements count] > 0 )
			{
				NSXMLElement *commit = [commitElements objectAtIndex: 0];
				NSArray *commitElements = [commit elementsForName: @"author"];
				if ( [commitElements count] > 0 )
				{
					theUser = [[commitElements objectAtIndex: 0] stringValue];
				}
				revisionLastChanged = [[commit attributeForName: @"revision"] stringValue];
			}
		}

		// <repos-status> node  (when running --show-update)
		NSXMLElement *repos_status = nil;
		NSArray *repos_status_elements = [entry elementsForName: @"repos-status"];

		NSString* reposItemStatus = nil;
		NSString* reposPropStatus = nil;
		NSString* repos_lock = nil;

		if ( [repos_status_elements count] > 0 )
		{
			repos_status = [repos_status_elements objectAtIndex: 0];

			if (kShowUpdates)
			{
				// repository lock?
				NSArray *lockInReposElements = [repos_status elementsForName: @"lock"];
				if ( [lockInReposElements count] > 0 )
				{
					NSXMLElement *lockInRepos = [lockInReposElements objectAtIndex: 0];
					repos_lock = [[[lockInRepos elementsForName: @"token"] objectAtIndex: 0] stringValue];
				}
			}

			reposItemStatus = [[repos_status attributeForName: @"item"] stringValue];
			reposPropStatus = [[repos_status attributeForName: @"props"] stringValue];

		}

	#if 0
		// local lock?
		NSXMLElement *lockInWc;

		if ( wc_status != nil )
		{
			NSArray *lockInWcElements = [wc_status elementsForName: @"lock"];

			if ( [lockInWcElements count] > 0 )
			{
				lockInWc = [lockInWcElements objectAtIndex: 0];
			}
		}
	#endif

		NSString* const itemFullPath = [[entry attributeForName: @"path"] stringValue];
		NSString* const itemPath = (targetPathLength < [itemFullPath length])
									? [itemFullPath substringFromIndex: targetPathLength + 1] : kCurrentDir;

		int col1 = ' ',  col2 = ' ';
		NSString *column1 = @" ";
		NSString *column2 = @" ";
		NSString *column3 = @" ";
		NSString *column4 = @" ";
		NSString *column5 = @" ";
		NSString *column6 = @" ";
		NSString *column7 = @" ";
		NSString *column8 = @" ";

		// see all meanings at http://svnbook.red-bean.com/nightly/en/svn.ref.svn.c.status.html
		// COLUMN 1
		const unichar ch0 = [itemStatus length] ? [itemStatus characterAtIndex: 0] : 0;
		if (ch0 == 0)
			;
		else if (ch0 == 'u' && [itemStatus isEqualToString: @"unversioned"])
		{
			col1 = '?';		column1 = @"?";
		}
		else if (ch0 == 'm' && [itemStatus isEqualToString: @"modified"])
		{
			col1 = 'M';		column1 = @"M";
		}
		else if (ch0 == 'a' && [itemStatus isEqualToString: @"added"])
		{
			col1 = 'A';		column1 = @"A";
		}
		else if (ch0 == 'd' && [itemStatus isEqualToString: @"deleted"])
		{
			col1 = 'D';		column1 = @"D";
		}
		else if (ch0 == 'r' && [itemStatus isEqualToString: @"replaced"])
		{
			col1 = 'R';		column1 = @"R";
		}
		else if (ch0 == 'c' && [itemStatus isEqualToString: @"conflicted"])
		{
			col1 = 'C';		column1 = @"C";
		}
		else if (ch0 == 'i' && [itemStatus isEqualToString: @"ignored"])
		{
			col1 = 'I';		column1 = @"I";
		}
		else if (ch0 == 'e' && [itemStatus isEqualToString: @"external"])
		{
			col1 = 'X';		column1 = @"X";
		}
		else if ((ch0 == 'i' && [itemStatus isEqualToString: @"incomplete"]) ||
				 (ch0 == 'm' && [itemStatus isEqualToString: @"missing"]))
		{
			col1 = '!';		column1 = @"!";
		}
		else if (ch0 == 'o' && [itemStatus isEqualToString: @"obstructed"])
		{
			col1 = '~';		column1 = @"~";
		}

		// COLUMN 2
		const unichar propStatusCh0 = (propStatus && [propStatus length]) ? [propStatus characterAtIndex: 0] : 0;
		if (propStatusCh0 == 'm' && [propStatus isEqualToString: @"modified"])
		{
			col2 = 'M';		column2 = @"M";
		}
		else if (propStatusCh0 == 'c' && [propStatus isEqualToString: @"conflicted"])
		{
			col2 = 'C';		column2 = @"C";
		}

		// COLUMN 3
		if ( [wcLockedStatus isEqualToString: @"true"] )
		{
			column3 = @"L";
		}

		// COLUMN 4
		if ( [copiedStatus isEqualToString: @"true"] )
		{
			column4 = @"+";
		}

		// COLUMN 5
		if ( [switchedStatus isEqualToString: @"true"] )
		{
			column5 = @"S";
		}

		// COLUMN 6
		// see <http://svn.collab.net/repos/svn/trunk/subversion/svn/status.c>, ~ line 112 for explanation
		if (kShowUpdates)
		{
			if ( repos_lock != nil )
			{
				if ( wc_lock != nil )
				{
				//	column6 = [[wc_lock objectForKey: @"token"] isEqualToString: repos_lock]
					column6 = [wc_lock isEqualToString: repos_lock]
								? @"K"	// File is locked in this working copy
								: @"T";	// File was locked in this working copy, but the lock has been 'stolen'
										// and is invalid. The file is currently locked in the repository
				}
				else
					column6 = @"O";		// File is locked either by another user or in another working copy
			}
			else if ( wc_lock )			// File was locked in this working copy, but the lock has
				 column6 = @"B";		// been 'broken' and is invalid. The file is no longer locked
		}
		else if ( wc_lock )
			column6 = @"K";				// File is locked in this working copy

		// COLUMN 7
		if ( repos_status != nil )
		{
			if ( [reposItemStatus isEqualToString: @"none"] == NO || [reposPropStatus isEqualToString: @"none"] == NO )
				column7 = @"*";
		}

		// COLUMN 8
		if (propStatusCh0 != 0 && (propStatusCh0 != 'n' || ![propStatus isEqualToString: @"none"]))
		{
			column8 = @"P";
		}

		BOOL renamable=NO, addable=NO, removable=NO, updatable=NO, revertible=NO, committable=NO,
			 copiable=NO, movable=NO, resolvable=NO, lockable=YES, unlockable=NO;

		if (col1 == 'M' || col2 == 'M')
		{
			removable = YES;
			updatable = YES;
			revertible = YES;
			committable = YES;
		}
		if (col1 == ' ')
		{
			removable = YES;
			renamable = YES;
			updatable = YES;
			copiable = YES;
			movable = YES;
		}
		else if (col1 == '?')
		{
			addable = YES;
			removable = YES;
			lockable = NO;
		}
		else if (col1 == '!')
		{
			revertible = YES;
			updatable = YES;
			removable = YES;
			lockable = NO;
		}
		else if (col1 == 'A' || col1 == 'R')
		{
			revertible = YES;
			committable = YES;
			lockable = NO;
			updatable = YES;
			removable = YES;
		}
		else if (col1 == 'D')
		{
			if ([fileManager fileExistsAtPath: itemFullPath])
				addable = YES;
			revertible = YES;
			committable = YES;
			updatable = YES;
		}
		else if (col1 == '~')	// obstructed
		{
			revertible = YES;
		}
		if (col1 == 'C'|| col2 == 'C')
		{
			revertible = YES;
			resolvable = YES;
		}
		if ( [column6 isEqualToString: @"K"])
		{
			lockable = NO;
			unlockable = YES;
		}

		NSString* const dirPath = [itemPath stringByDeletingLastPathComponent];
		BOOL isDir = NO;

		if (!kFlatMode && itemPath != kCurrentDir &&
			[fileManager fileExistsAtPath: itemFullPath isDirectory: &isDir] && isDir)
		{
			NSArray* const pathArr = [itemPath componentsSeparatedByString: @"/"];
			const unsigned int wcPathLength = [workingCopyPath length] + 1;

			NSString* filePath = workingCopyPath;
			id tmp = rootChildren;		// let's start at root
			int j, count = [pathArr count];

			for (j = 0; j < count; ++j)
			{
				ConstString dirName = [pathArr objectAtIndex: j];
				id child = nil;
				filePath = [filePath stringByAppendingPathComponent: dirName];

				for_each_obj(en, obj, tmp)
				{
					if ([[obj name] isEqualToString: dirName])
					{
						child = obj;
						break;
					}
				}

				if (child == nil)
				{
					child = [WCTreeEntry create: [NSMutableArray array]
										   name: dirName
										   path: [filePath substringFromIndex: wcPathLength]];
					[tmp addObject: child];
					[child release];
				}

				tmp = [child children];
			}
		}

		[newSvnFiles addObject: [NSDictionary dictionaryWithObjectsAndKeys:
									column1, @"col1",
									column2, @"col2",
									column3, @"col3",
									column4, @"col4",
									column5, @"col5",
									column6, @"col6",
									column7, @"col7",
									column8, @"col8",
									revisionCurrent, @"revisionCurrent",
									revisionLastChanged, @"revisionLastChanged",
									theUser, @"user",
									(kFlatMode ? itemPath : [itemPath lastPathComponent]), @"displayPath",
									itemPath, @"path",
									itemFullPath, @"fullPath",
									dirPath, @"dirPath",
									NSBool(isDir), @"isDir",	// NOTE: Only valid if !kFlatMode

									NSBool(col1 == 'M'), @"modified",
									NSBool(col1 == '?'), @"new",
									NSBool(col1 == '!'), @"missing",
									NSBool(col1 == 'A'), @"added",
									NSBool(col1 == 'D'), @"deleted",

									NSBool(renamable  ), @"renamable",
									NSBool(addable    ), @"addable",
									NSBool(removable  ), @"removable",
									NSBool(updatable  ), @"updatable",
									NSBool(revertible ), @"revertible",
									NSBool(committable), @"committable",
									NSBool(resolvable ), @"resolvable",
									NSBool(lockable   ), @"lockable",
									NSBool(unlockable ), @"unlockable",

									nil]];
	}
	[pool release];
	[xmlDoc release];

	if (outlineDirs)
		[self setSvnDirectories: outlineDirs];
	[self setSvnFiles: newSvnFiles];
}


//----------------------------------------------------------------------------------------
#pragma mark	svn info
//----------------------------------------------------------------------------------------

- (void) fetchSvnInfo
{
	if (fInfoPending || !useOldParsingMethod())
		return;

	fInfoPending = TRUE;
	[MySvn    genericCommand: @"info"
				   arguments: [NSArray arrayWithObject: [self workingCopyPath]]
			  generalOptions: [self svnOptionsInvocation]
					 options: nil
					callback: MakeCallbackInvocation(self, @selector(svnInfoCompletedCallback:))
				callbackInfo: nil
					taskInfo: [self documentNameDict]];
}


//----------------------------------------------------------------------------------------

- (void) svnInfo: (id) pathOrPaths
		 options: (id) options
{
	if (pathOrPaths == nil)
		pathOrPaths = workingCopyPath;
	if (!ISA(pathOrPaths, NSArray))
		pathOrPaths = [NSArray arrayWithObject: pathOrPaths];
	if (options && !ISA(options, NSArray))
		options = [NSArray arrayWithObject: options];
	[self setDisplayedTaskObj:
		[MySvn genericCommand: @"info"
					arguments: pathOrPaths
			   generalOptions: [self svnOptionsInvocation]
					  options: options
					 callback: MakeCallbackInvocation(self, @selector(emptyCallback:))
				 callbackInfo: nil
					 taskInfo: [self documentNameDict]]];
}


//----------------------------------------------------------------------------------------
// WC 'svn info' callback.  Sets <revision> and <repositoryUrl>.

- (void) svnInfo: (SvnInfo)   info
		 forPath: (ConstCStr) path
{
	#pragma unused(path)
//	dprintf("revision=%d url=<%s>", info->rev, info->URL);
	[self setRevision: SvnRevNumToString(info->rev)];

	NSString* urlString = UTF8(info->URL);
	if ([urlString characterAtIndex: [urlString length] - 1] != '/')
		urlString = [urlString stringByAppendingString: @"/"];

	[self setRepositoryUrl: [NSURL URLWithString: urlString]];
}


//----------------------------------------------------------------------------------------

- (void) svnInfoCompletedCallback: (id) taskObj
{
	fInfoPending = FALSE;
	if (isCompleted(taskObj))
	{
		[self fetchSvnInfoReceiveDataFinished: stdOut(taskObj)];
	}

	[self svnError: taskObj];
}


//----------------------------------------------------------------------------------------

- (void) fetchSvnInfoReceiveDataFinished: (NSString*) result
{
	NSArray* const lines = [result componentsSeparatedByString: @"\n"];

	const int count = [lines count];
	if (count < 5)
	{
		[controller svnError: result];
	}
	else
	{
		bool gotRev = false, gotURL = false;
		for (int i = 0; i < count && (!gotRev || !gotURL); ++i)
		{
			ConstString line = [lines objectAtIndex: i];
			const int lineLength = [line length];

			if (!gotRev && lineLength > 9 && [line beginsWith: @"Revision: "])
			{
				[self setRevision: [line substringFromIndex: 10]];
				gotRev = true;
			}
			else if (!gotURL && lineLength > 4 && [line beginsWith: @"URL: "])
			{
				NSString* urlString = [line substringFromIndex: 5];

				if ([urlString characterAtIndex: [urlString length] - 1] != '/')
					urlString = [urlString stringByAppendingString: @"/"];

				[self setRepositoryUrl: [NSURL URLWithString: urlString]];
				gotURL = true;
			}
		}
	}
}


//----------------------------------------------------------------------------------------
#pragma mark	svn commit
//----------------------------------------------------------------------------------------

- (void) svnCommit:    (NSArray*)      items
		 message:      (NSString*)     message
		 callback:     (NSInvocation*) callback
		 callbackInfo: (id)            callbackInfo
{
	AssertClass([items objectAtIndex: 0], NSDictionary);

	// Cannot non-recursively commit a directory deletion, i.e. must not use --non-recursive
	// when committing a directory deletion, but we want to use it if possible to prevent
	// commiting files in a dir if only a prop-change commit was requested on the dir.
	BOOL nonRecusive = TRUE, isDir;
	NSFileManager* const fileManager = [NSFileManager defaultManager];
	for_each_obj(enumerator, item, items)
	{
		if ([[item objectForKey: @"deleted"] boolValue] &&
			[fileManager fileExistsAtPath: [item objectForKey: @"fullPath"] isDirectory: &isDir] &&
			isDir)
		{
			nonRecusive = FALSE;
			break;
		}
	}

	NSArray* itemPaths = [items valueForKey: @"fullPath"];

	NSArray* options = [NSArray arrayWithObjects: @"-m", MessageString(message),
												  (nonRecusive ? @"--non-recursive" : nil),
												  nil];
	id taskObj = [MySvn genericCommand: @"commit"
							 arguments: itemPaths
						generalOptions: [self svnOptionsInvocation]
							   options: options
							  callback: callback
						  callbackInfo: callbackInfo
							  taskInfo: [self documentNameDict]];
	[self setDisplayedTaskObj: taskObj];
}


//----------------------------------------------------------------------------------------

- (void) svnCommit: (NSString*) message
{
	[self svnCommit:    [svnFilesAC selectedObjects]
		  message:      message
		  callback:     [self genericCompletedCallback]
		  callbackInfo: nil];
}


//----------------------------------------------------------------------------------------
#pragma mark	svn cleanup
//----------------------------------------------------------------------------------------

- (void) svnCleanup: (id) paths
{
	[self setDisplayedTaskObj:
		[MySvn genericCommand: @"cleanup"
					arguments: paths ? paths : [NSArray arrayWithObject: workingCopyPath]
			   generalOptions: [self svnOptionsInvocation]
					  options: nil
					 callback: MakeCallbackInvocation(self, @selector(emptyCallback:))
				 callbackInfo: nil
					 taskInfo: [self documentNameDict]]];
}


//----------------------------------------------------------------------------------------
#pragma mark	svn merge
//----------------------------------------------------------------------------------------

- (void) svnMerge: (BOOL)     dryRun
		 options:  (NSArray*) options
{
	NSInvocation* callback = dryRun ? MakeCallbackInvocation(self, @selector(svnError:))
									: [self genericCompletedCallback];
	id taskObj = [MySvn genericCommand: @"merge"
							 arguments: [NSArray arrayWithObjects: dryRun ? @"--dry-run" : nil, nil]
						generalOptions: [self svnOptionsInvocation]
							   options: options
							  callback: callback
						  callbackInfo: nil
							  taskInfo: [self documentNameDict]];
	if (dryRun)
		[[taskObj objectForKey: @"additionalTaskInfo"] setObject: @"svn merge (dry run)"
														  forKey: @"name"];
	[self setDisplayedTaskObj: taskObj];
	if (dryRun)
		[controller performSelector: @selector(openSidebar) withObject: nil afterDelay: 0.25];
	else
		[controller startProgressIndicator];
}


//----------------------------------------------------------------------------------------
#pragma mark	svn switch
//----------------------------------------------------------------------------------------

- (void) svnSwitch: (NSArray*) options
{
	// it would be much more clean to use a specific [MySvn switch: ...] command.
	id taskObj = [MySvn genericCommand: @"switch"
							 arguments: [NSArray array]
						generalOptions: [self svnOptionsInvocation]
							   options: options
							  callback: [self genericCompletedCallback]
						  callbackInfo: nil
							  taskInfo: [self documentNameDict]];
	[self setDisplayedTaskObj: taskObj];
}


//----------------------------------------------------------------------------------------
#pragma mark	svn generic command
//----------------------------------------------------------------------------------------

- (void) svnCommand: (NSString*)     command
		 options:    (NSArray*)      options
		 info:       (NSDictionary*) info
		 itemPaths:  (NSArray*)      itemPaths
{
	if (itemPaths == nil)
		itemPaths = [[svnFilesAC selectedObjects] valueForKey: @"fullPath"];
//	dprintf("itemPaths=%@", itemPaths);
	if (options == nil)
		options = [NSArray array];

	[controller startProgressIndicator];
	NSInvocation* const callback = [self genericCompletedCallback];
	NSDictionary* const taskInfo = [self documentNameDict];
	TaskObj* taskObj = nil;

	if ([command isEqualToString: @"rename"])
	{
		NSMutableArray* srcAndDst = [NSMutableArray arrayWithArray: itemPaths];
		[srcAndDst addObject: [info objectForKey: @"destination"]];

		taskObj =
		[MySvn   genericCommand: @"move"
					  arguments: srcAndDst
				 generalOptions: [self svnOptionsInvocation]
						options: options
					   callback: callback
				   callbackInfo: nil
					   taskInfo: taskInfo];
	}
	else if ([command isEqualToString: @"move"])
	{
		taskObj =
		[MySvn     moveMultiple: itemPaths
					destination: [info objectForKey: @"destination"]
				 generalOptions: [self svnOptionsInvocation]
						options: options
					   callback: callback
				   callbackInfo: nil
					   taskInfo: taskInfo];
	}
	else if ([command isEqualToString: @"copy"])
	{
		taskObj =
		[MySvn     copyMultiple: itemPaths
					destination: [info objectForKey: @"destination"]
				 generalOptions: [self svnOptionsInvocation]
						options: options
					   callback: callback
				   callbackInfo: nil
					   taskInfo: taskInfo];
	}
	else // ...
	{
		Assert(![command isEqualToString: @"switch"]);
		Assert(![command isEqualToString: @"commit"]);
		taskObj =
		[MySvn   genericCommand: command
					  arguments: itemPaths
				 generalOptions: [self svnOptionsInvocation]
						options: options
					   callback: callback
				   callbackInfo: nil
					   taskInfo: taskInfo];
	}
	[self setDisplayedTaskObj: taskObj];
}


//----------------------------------------------------------------------------------------

- (void) svnGenericCompletedCallback: (id) taskObj
{
	[controller stopProgressIndicator];

	if (isCompleted(taskObj))
	{
		[self svnRefresh];
	}

	[self svnError: taskObj];
}


//----------------------------------------------------------------------------------------
#pragma mark	svn update
//----------------------------------------------------------------------------------------

- (void) svnUpdate: (NSArray*) options
		 items:     (NSArray*) itemPaths	// nil => workingCopyPath
{
	[self svnCommand: @"update" options: options info: nil
		   itemPaths: itemPaths ? itemPaths : [NSArray arrayWithObject: workingCopyPath]];
}


//----------------------------------------------------------------------------------------
// Update entire working copy to HEAD

- (void) svnUpdate
{
	[self svnUpdate: nil items: nil];
}


//----------------------------------------------------------------------------------------
#pragma mark	svn diff
//----------------------------------------------------------------------------------------

- (NSDictionary*) findRootItem
{
	for_each_obj(en, it, svnFiles)
		if ([it objectForKey: @"path"] == kCurrentDir)
			return it;
	return nil;
}


//----------------------------------------------------------------------------------------

- (void) svnDiff:      (NSArray*)      items
		 options:      (id)            options
		 callback:     (NSInvocation*) callback
		 callbackInfo: (id)            callbackInfo
{
	if (ISA(options, NSString))
		options = [NSArray arrayWithObject: options];
	[MySvn	diffItems: items
	   generalOptions: [self svnOptionsInvocation]
			  options: options
			 callback: callback
		 callbackInfo: callbackInfo
			 taskInfo: [self documentNameDict]];
}


//----------------------------------------------------------------------------------------

- (void) diffItems:    (NSArray*)      items
		 callback:     (NSInvocation*) callback
		 callbackInfo: (id)            callbackInfo
{
	[self svnDiff: items
		  options: nil
		 callback: callback
	 callbackInfo: callbackInfo];
}


//----------------------------------------------------------------------------------------

- (void) svnDiff: (NSArray*) items
		 options: (id)       options
{
	[self svnDiff: items
		  options: options
		 callback: MakeCallbackInvocation(self, @selector(diffCallback:))
	 callbackInfo: nil];
}


//----------------------------------------------------------------------------------------

- (void) diffItems: (NSArray*) items
{
	[self svnDiff: items options: nil];
}


//----------------------------------------------------------------------------------------

- (void) diffCallback: (id) taskObj
{
	if (isCompleted(taskObj))
		;

	[self svnError: taskObj];
}


//----------------------------------------------------------------------------------------
#pragma mark	svn resolve
//----------------------------------------------------------------------------------------
// svnresolve.sh <svn-tool> <diff-app> <wc-file-path…>

- (void) svnResolve: (NSArray*) items
{
	[MySvn runScript: @"svnresolve"
			 options: [NSArray arrayWithObjects: SvnCmdPath(), GetDiffAppName(), nil]
				args: items
				name: @"resolve"
			callback: MakeCallbackInvocation(self, @selector(diffCallback:))
		callbackInfo: nil
			taskInfo: [self documentNameDict]
			dataOnly: NO];
}


//----------------------------------------------------------------------------------------
// AppleScript.  Interactively resolve conflicts in file <path> if it belongs to this WC.

- (BOOL) resolveFiles: (NSString*) path
{
	for_each_obj(en, it, svnFiles)
	{
		if ([[it objectForKey: @"fullPath"] isEqualToString: path])
		{
			[self svnResolve: [NSArray arrayWithObject: path]];
			return YES;
		}
	}
	return NO;
}


//----------------------------------------------------------------------------------------
#pragma mark	svn proplist
//----------------------------------------------------------------------------------------

const NSIndex kBaseArgs = 2, kMaxArgs = 45;

static inline NSString* NewString_	(NSData* data)
{ return [[[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding] autorelease]; }


//----------------------------------------------------------------------------------------

static SvnString
SvnNewString (SvnPool pool, id value)
{
	if (value)
	{
		if (ISA(value, NSData))
			return svn_string_ncreate([value bytes], [value length], pool);
		return svn_string_create([value UTF8String], pool);
	}
	return NULL;
}


//----------------------------------------------------------------------------------------
// Performs a single run of `svn proplist <paths...>` then parses the output &
// runs `svn propget <name> <path>` for each non-const-prop, as necessary.

static void
getSvnProps (NSString* args[], int count, NSDictionary* constProps, NSMutableArray* result)
{
	//dprintf("paths=%d", count);
	Assert(1 <= count && count <= kMaxArgs - kBaseArgs);
	NSData* stdOut = nil, *stdErr = nil;
	int status = SvnRun([NSArray arrayWithObjects: args  count: count + kBaseArgs], &stdOut, &stdErr, 0);
	if (status == 0 && [stdErr length] == 0)
	{
		NSMutableData* const data = (NSMutableData*) stdOut;
		[data appendBytes: "\0\0\0" length: 4];
		char* p = [data mutableBytes];
		int arg = kBaseArgs;
		// Parse output of `svn proplist <paths...>`.
		while (memcmp(p, "Properties on '", 15) == 0)
		{
			p += 15;
			ConstCStr str = p;
			for ( ; *p++ != '\n'; )
				if (*p == 0)
					return;
			Assert(p[-3] == '\'' && p[-2] == ':');
			NSString* fullPath;
			if (count != 1)
			{
				p[-3] = 0;
				ConstString path = UTF8(str);
				while (![path isEqualToString: fullPath = args[arg]])
					if (++arg >= count + kBaseArgs)
						return;
	//			dprintf_("path=\"%@\"", fullPath);
			}
			else
				fullPath = args[arg];

			NSMutableDictionary* dict = nil;
			while (*p == ' ')
			{
				if (*++p == ' ')
					++p;
				str = p;
				while (*p && *p != '\n')
					++p;
				if (p == str)
					return;
				*p++ = 0;
				ConstString name = UTF8(str);
	//			dprintf_("    prop=\"%@\"", name);
				id value = [constProps objectForKey: name];
				if (!value)
				{
					status = SvnRun([NSArray arrayWithObjects: @"propget", name, @"--non-interactive",
											 @"--strict", fullPath, nil], &stdOut, &stdErr, 0);
					if (status == 0 && [stdErr length] == 0)
					{
						if (stdOut == nil)
							value = @"???";
						else if ((value = NewString_(stdOut)) != nil)
							;
						else
							value = stdOut;
					}
					else
						dprintf("ERROR: [propget '%@' status=%d] %@", name, status, NewString_(stdErr));
				}
	//			dprintf_("    value=\"%@\"", value);
				if (value)
				{
					if (dict == nil)
						dict = [NSMutableDictionary dictionaryWithObject: fullPath forKey: @".path"];
					[dict setObject: value forKey: name];
				}
			}
			if (dict != nil)
				[result addObject: dict];
			if (++arg >= count + kBaseArgs)
				break;
		}
	}
	else
		dprintf("ERROR: [status=%d args=%@] %@",
				status, [NSArray arrayWithObjects: args count: count], NewString_(stdErr));
}


//----------------------------------------------------------------------------------------

- (NSArray*) svnPropListTask: (NSArray*)      items
			 constProps:      (NSDictionary*) constProps
			 count:           (UInt32*)       itemCount
{
	NSMutableArray* const result = [NSMutableArray array];
	UInt32 icount = 0;
	NSAutoreleasePool* autoPool = [NSAutoreleasePool new];

	@try
	{
		id args[kMaxArgs]; int count = 0;
		args[0] = @"proplist";
		args[1] = @"--non-interactive";
		for_each_obj(en, it, items)
		{
			const int status = [[it objectForKey: @"col1"] characterAtIndex: 0];
			if (status == '?' || status == 'D')
				continue;										// Skip unversioned or deleted items
			++icount;
			if (status != 'A' && [[it objectForKey: @"col8"] isEqualTo: @" "])
				continue;										// Skip items with no properties (except new items)

			args[count++ + kBaseArgs] = [it objectForKey: @"fullPath"];
			if (count > kMaxArgs - 6)
			{
				getSvnProps(args, count, constProps, result);
				count = 0;
			}
		}
		if (count)
			getSvnProps(args, count, constProps, result);
	}
	@finally
	{
		[autoPool release];
	}

	*itemCount = icount;
	return result;
}


//----------------------------------------------------------------------------------------
// Input <items> contains 0 or more WCItems from this WC.
// Returns an NSArray of dictionaries containing svn property key-values.
// Returns the count of available items in itemCount.

- (NSArray*) svnPropList: (NSArray*)      items
			 constProps:  (NSDictionary*) constProps
			 count:       (UInt32*)       itemCount
{
	typedef apr_hash_t*					SvnHash;
	typedef apr_hash_index_t*			SvnHashIndex;
	typedef svn_client_proplist_item_t*	SvnProplistItem;

	*itemCount = 0;
	if (items == nil || [items count] == 0)
		return nil;

	if (!SvnWantAndHave())
		return [self svnPropListTask: items constProps: constProps count: itemCount];

//	dprintf("fWorkingCopyPath='%@' items=%d", fWorkingCopyPath, Size(items));
	NSMutableArray* const result = [NSMutableArray array];

	UInt32 count = 0;
	NSAutoreleasePool* autoPool = [NSAutoreleasePool new];
	const SvnPool pool = SvnNewPool();
	@try
	{
		const SvnClient ctx = SvnSetupClient(&fSvnEnv, self);
		const SvnOptRevision rev_opt = { svn_opt_revision_working };
		for_each_obj(en, it, items)
		{
			const int status = [[it objectForKey: @"col1"] characterAtIndex: 0];
			if (status == '?' || status == 'D')
				continue;										// Skip unversioned or deleted items
			++count;
			if (status != 'A' && [[it objectForKey: @"col8"] isEqualTo: @" "])
				continue;										// Skip items with no properties (except new items)
			ConstString fullPath = [it objectForKey: @"fullPath"];
			char path[PATH_MAX];
			if (![fullPath getFileSystemRepresentation: path maxLength: sizeof(path)])
				continue;

			SvnArray plist = NULL;
			SvnError err = svn_client_proplist2(&plist, path, &rev_opt, &rev_opt,
												!kSvnRecurse, ctx, pool);
			if (err)
			{
				if (err->apr_err != SVN_ERR_ENTRY_NOT_FOUND)	// Don't report unversioned file error
					dprintf("path=\"%@\"\n    err=%s", fullPath, err->message);
				continue;
			}
			if (plist == NULL || plist->nelts <= 0)
				continue;

			NSMutableDictionary* dict = nil;
			for (int i = 0; i < plist->nelts; ++i)
			{
				SvnHash props = ((SvnProplistItem*) (plist->elts))[i]->prop_hash;
				for (SvnHashIndex hi = apr_hash_first(pool, props); hi != NULL; hi = apr_hash_next(hi))
				{
					ConstCStr key = NULL;
					SvnString value = NULL;
					apr_hash_this(hi, (const void**) &key, NULL, (void**) &value);
					if (key == NULL || value == NULL)
						continue;

					if (dict == nil)
						dict = [NSMutableDictionary dictionaryWithObject: fullPath forKey: @".path"];
					id val = UTF8_(value->data, value->len);
					if (val != nil)
						[val autorelease];
					else
						val = [NSData dataWithBytes: value->data length: value->len];
					[dict setObject: val ? val : @"???" forKey: UTF8(key)];
				}
			}
			if (dict != nil)
				[result addObject: dict];
		}
	}
	@finally
	{
		SvnDeletePool(pool);
		[autoPool release];
	}

//	dprintf("result=%@ count=%u", result, count);
	*itemCount = count;
	return result;
}


//----------------------------------------------------------------------------------------

- (void) svnPropSet: (NSString*) name
		 value:      (id)        value	// NSString, NSData or nil to delete
		 items:      (NSArray*)  paths
{
//	dprintf("Set property '%@' to '%@' for %@.", name, value, paths);
	if ([name length] == 0 || [paths count] == 0)
		return;

	const bool useLibs = SvnWantAndHave();
	NSAutoreleasePool* autoPool = [NSAutoreleasePool new];
	const SvnPool pool = useLibs ? SvnNewPool() : NULL;
	@try
	{
		if (useLibs)
		{
			const SvnClient ctx = SvnSetupClient(&fSvnEnv, self);
			const ConstCStr propname = [name UTF8String];
			const SvnString propval = SvnNewString(pool, value);
			for_each_obj(en, it, paths)
			{
				char path[PATH_MAX];
				if ([it getFileSystemRepresentation: path maxLength: sizeof(path)])
					SvnThrowIf(svn_client_propset2(propname, propval, path, !kSvnRecurse,
												   /*skip_checks*/ NO, ctx, pool));
			}
		}
		else	// Run svn tool: `svn propset <name> (<value> | --file <tmp-file> files...`
		{		//			  or `svn propdel <name> files...`
			NSString* tmpFile = nil;
			id objs[8]; int count = 0;
			objs[count++] = value ? @"propset" : @"propdel";
			objs[count++] = name;

			if (ISA(value, NSString) && [value length] > 0 && [value characterAtIndex: 0] == '-')
				value = [value dataUsingEncoding: NSUTF8StringEncoding];	// Use --file for "-*" values
			if (value == nil)
				;	// propdel
			else if (ISA(value, NSData))
			{
				objs[count++] = @"--file";
				tmpFile = [NSString stringWithFormat: @"/tmp/svnx-prop-%u", getpid()];
				if (![value writeToFile: tmpFile atomically: NO])
					@throw tmpFile;
				objs[count++] = tmpFile;
			}
			else
				objs[count++] = MessageString(value);	// Prevent decomposing combining diacritical marks
			objs[count++] = @"--non-interactive";
			if (value)
				objs[count++] = @"--force";
			Assert(3 <= count && count <= 6);
			NSMutableArray* const args = [NSMutableArray arrayWithObjects: objs count: count];
			[args addObjectsFromArray: paths];
			NSData* stdOut = nil, *stdErr = nil;
			int status = SvnRun(args, &stdOut, &stdErr, 0);
			if (status != 0 || [stdErr length] != 0)
				dprintf("ERROR: [status=%d args=%@] %@", status, args, NewString_(stdErr));
			if (tmpFile)
				[[NSFileManager defaultManager] removeFileAtPath: tmpFile handler: nil];
		}
	}
	@finally
	{
		SvnDeletePool(pool);
		[autoPool release];
	}
	[self svnRefresh];
}


//----------------------------------------------------------------------------------------

- (void) svnPropDel: (NSString*) name
		 items:      (NSArray*)  paths
{
	dprintf("Del property '%@' for %@.", name, paths);
	[self svnPropSet: name value: nil items: paths];
}


//----------------------------------------------------------------------------------------
#pragma mark	-
#pragma mark	Helpers
//----------------------------------------------------------------------------------------

- (NSMutableDictionary*) getSvnOptions
{
	return [NSMutableDictionary dictionaryWithObjectsAndKeys: [self user], @"user", [self pass], @"pass", nil ];
}


//----------------------------------------------------------------------------------------

- (void) emptyCallback: (TaskObj*) taskObj
{
	#pragma unused(taskObj)
}


//----------------------------------------------------------------------------------------

- (void) observeValueForKeyPath: (NSString*)     keyPath
		 ofObject:               (id)            object
		 change:                 (NSDictionary*) change
		 context:                (void*)         context
{
	#pragma unused(object, change, context)
//	dprintf("keyPath='%@'", keyPath);

	if ([keyPath isEqualToString: keySmartMode])
	{
		if (smartMode)
			flatMode = YES;
		[controller adjustOutlineView];
		[self svnRefresh];
	}
	else if ([keyPath isEqualToString: keyFlatMode])
	{
		if (!flatMode)
			smartMode = NO;
		[self svnRefresh];
	}
	else if ([keyPath isEqualToString: keyShowExternals])
	{
		gShowExternals = GetPreferenceBool(keyShowExternals);
		[self svnRefresh];
	}

//	dprintf("---");
}


//----------------------------------------------------------------------------------------
#pragma mark	-
#pragma mark	Accessors
//----------------------------------------------------------------------------------------

- (NSInvocation*) svnOptionsInvocation
{
	return MakeCallbackInvocation(self, @selector(getSvnOptions));
}


//----------------------------------------------------------------------------------------
// get/set displayedTaskObj

- (NSMutableDictionary*) displayedTaskObj { return displayedTaskObj; }

- (void) setDisplayedTaskObj: (NSMutableDictionary*) taskObj
{
	id old = displayedTaskObj;
	displayedTaskObj = [taskObj retain];
	[old release];
}


//----------------------------------------------------------------------------------------
// get/set user name

- (NSString*) user { return user; }

- (void) setUser: (NSString*) aUser
{
	id old = user;
	user = [aUser retain];
	[old release];
}


//----------------------------------------------------------------------------------------
// get/set user password

- (NSString*) pass { return pass; }

- (void) setPass: (NSString*) aPass
{
	id old = pass;
	pass = [aPass retain];
	[old release];
}


//----------------------------------------------------------------------------------------
// get/set svnFiles

- (NSArray*) svnFiles { return svnFiles; }

- (void) setSvnFiles: (NSArray*) aSvnFiles
{
	if (svnFiles != aSvnFiles)
	{
		[svnFiles release];
		svnFiles = [aSvnFiles retain];
	}
}


//----------------------------------------------------------------------------------------
// get/set revision

- (SvnRevNum) revisionNum { return SvnRevNumFromString(revision); }

- (NSString*) revision { return revision; }

- (void) setRevision: (NSString*) aRevision
{
	id old = [self revision];
	revision = [aRevision retain];
	[old release];
}


//----------------------------------------------------------------------------------------
// get/set workingCopyPath

- (NSString*) workingCopyPath { return workingCopyPath; }

- (void) setWorkingCopyPath: (NSString*) str
{
	id old = workingCopyPath;
	workingCopyPath = [str retain];
	[old release];
}


//----------------------------------------------------------------------------------------
// get/set svnDirectories

- (WCTreeEntry*) svnDirectories { return svnDirectories; }

- (void) setSvnDirectories: (WCTreeEntry*) aSvnDirectories
{
	const id old = svnDirectories;
	if (aSvnDirectories != old)
	{
		svnDirectories = aSvnDirectories;
		[old autorelease];
	}
}


//----------------------------------------------------------------------------------------
// filterMode: set by the toolbar pop-up menu

- (int) filterMode { return filterMode; }

- (void) setFilterMode: (int) aFilterMode
{
//	dprintf("%d", aFilterMode);
	filterMode = aFilterMode;
}


//----------------------------------------------------------------------------------------
// get/set windowTitle

- (NSString*) windowTitle { return windowTitle; }

- (void) setWindowTitle: (NSString*) aWindowTitle
{
	id old = windowTitle;
	windowTitle = [aWindowTitle retain];
	[old release];
}


//----------------------------------------------------------------------------------------
// get/set flatMode

- (BOOL) flatMode { return flatMode; }

- (void) setFlatMode: (BOOL) flag
{
	flatMode = flag;
}


//----------------------------------------------------------------------------------------
// get/set smartMode

- (BOOL) smartMode { return smartMode; }

- (void) setSmartMode: (BOOL) flag
{
	smartMode = flag;
}


//----------------------------------------------------------------------------------------

- (IconRef) iconForFile: (NSString*) relPath
{
	Boolean isDirectory = TRUE;
	char path[2048];
	if (!ToUTF8([workingCopyPath stringByAppendingPathComponent: relPath], path, sizeof(path)))
		path[0] = 0;

	return GetFileIcon(path, &isDirectory);
}


//----------------------------------------------------------------------------------------

- (id) treeSelectedItem
{
	ConstString path = outlineSelectedPath;
	if (!flatMode && path)
	{
		for_each_obj(en, it, svnFiles)
			if ([[it objectForKey: @"isDir"] boolValue] &&
				[path isEqualToString: [it objectForKey: @"path"]])
				return it;
	}

	return nil;
}


//----------------------------------------------------------------------------------------

- (NSString*) treeSelectedFullPath
{
	return [workingCopyPath stringByAppendingPathComponent: outlineSelectedPath];
}


//----------------------------------------------------------------------------------------
// get/set outlineSelectedPath

- (NSString*) outlineSelectedPath { return outlineSelectedPath; }

- (void) setOutlineSelectedPath: (NSString*) aPath
{
//	dprintf("('%@')", aPath);
	Assert(aPath != nil);
	SetVar(outlineSelectedPath, aPath);
	if (svnFiles != nil)
		[svnFilesAC rearrangeObjects];
}


//----------------------------------------------------------------------------------------

- (id) controller
{
	return controller;
}


//----------------------------------------------------------------------------------------
// get/set repositoryUrl

- (NSURL*) repositoryUrl { return repositoryUrl; }

- (void) setRepositoryUrl: (NSURL*) aRepositoryUrl
{
	id old = [self repositoryUrl];
	repositoryUrl = [aRepositoryUrl retain];
	[old release];
}


@end	// MyWorkingCopy


//----------------------------------------------------------------------------------------
#pragma mark -
//----------------------------------------------------------------------------------------
// Compare names alphabetically & case insensitively.

static int
compareNames (id obj1, id obj2, void* context)
{
	#pragma unused(context)
	return [[obj1 name] compare: [obj2 name] options: kSortOptions];
}


//----------------------------------------------------------------------------------------

@implementation WCTreeEntry


+ (id) create: (NSMutableArray*) itsChildren
	   name:   (NSString*)       itsName
	   path:   (NSString*)       itsPath
{
	WCTreeEntry* obj = [self alloc];
	if (obj)
	{
		obj->children = [itsChildren retain];
		obj->name     = [itsName     retain];
		obj->path     = [itsPath     retain];
	}

//	dprintf("%@: '%@'", obj, itsPath);
	return obj;
}


//----------------------------------------------------------------------------------------

- (void) dealloc
{
	[children release];
	[name     release];
	[path     release];
	if (icon)
		WarnIf(ReleaseIconRef(icon));
	[super dealloc];
}


//----------------------------------------------------------------------------------------

- (int) childCount
{
	return [children count];
}


//----------------------------------------------------------------------------------------

- (id) childAtIndex: (int) index
{
	if (!sorted)
	{
		[children sortUsingFunction: compareNames context: NULL];
		sorted = TRUE;
	}

	return [children objectAtIndex: index];
}


//----------------------------------------------------------------------------------------

- (NSMutableArray*) children
{
	return children;
}


//----------------------------------------------------------------------------------------

- (NSString*) name
{
	return name;
}


//----------------------------------------------------------------------------------------

- (NSString*) path
{
	return path;
}


//----------------------------------------------------------------------------------------

- (IconRef) icon: (MyWorkingCopy*) workingCopy
{
	if (icon == NULL)
		icon = [workingCopy iconForFile: path];

	return icon;
}


@end	// WCTreeEntry

//----------------------------------------------------------------------------------------
// End of MyWorkingCopy.m

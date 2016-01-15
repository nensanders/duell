package duell.versioning.locking;

import sys.FileSystem;
import sys.io.File;
import haxe.io.Path;

import duell.helpers.LogHelper;
import duell.helpers.GitHelper;
import duell.objects.Haxelib;
import duell.objects.DuellLib;
import duell.versioning.objects.LockedVersion;
import duell.versioning.locking.file.ILockingFileParser;
import duell.versioning.locking.file.LockingFileXMLParser;

typedef LockedLibraries = {
	duelllibs : Array<DuellLib>,
	haxelibs : Array<Haxelib>,
	plugins : Array<DuellLib>
}

class LockedVersionsHelper
{
	private static inline var DEFAULT_FOLDER = 'versions';
	private static inline var DEFAULT_FILE = 'lockedVersions.xml';

	private static var versionMap = new Map<String, LockedVersions>();

	public static function getLastLockedVersion( path:String ) : LockedLibraries 
	{
		path = path == '' ? Path.join([Sys.getCwd(), DEFAULT_FOLDER, DEFAULT_FILE]) : path;

		if(!versionMap.exists( path ))
		{
			var versions = new LockedVersions(new LockingFileXMLParser(), path);
			versions.loadAndParseFile();

			versionMap.set( path, versions );
		}

		var versions = versionMap.get( path );

		return versions.getLastLockedLibraries();
	}

	public static function addLockedVersion( duelllibs:Array<DuellLib>, haxelibs:Array<Haxelib>, plugins:Array<DuellLib> )
	{
		var path = Path.join([Sys.getCwd(), DEFAULT_FOLDER, DEFAULT_FILE]);

		if(!versionMap.exists( path ))
		{
			var versions = new LockedVersions(new LockingFileXMLParser(), path);
			versions.setupFileSystem();
			versions.loadAndParseFile();

			versionMap.set(path, versions);
		}

		var versions = versionMap.get( path );
		versions.addLibraries( duelllibs, haxelibs, plugins );
	}
}


class LockedVersions 
{
	private static inline var NUMBER_MAX_TRACKED_VERSIONS : Int = 5;

	public var lockedVersions(default, null) : Array<LockedVersion>;
	private var parser : ILockingFileParser;
	private var path : String;

	public function new( parser:ILockingFileParser, path:String )
	{
		lockedVersions = new Array<LockedVersion>();
		this.parser = parser;
		this.path = path;
	}

	public function setupFileSystem()
	{
		var dir = Path.directory( path );
		if(!FileSystem.exists( dir ))
		{
			FileSystem.createDirectory( dir );
		}
	}

	public function loadAndParseFile()
	{
		var stringContent = "";
		if(FileSystem.exists( path ))
		{
			stringContent = File.getContent( path );
		}

		lockedVersions = parser.parseFile( stringContent );
	}

	public function getLastLockedVersion() : LockedVersion
	{
		var version : LockedVersion = null;
		for ( lv in lockedVersions )
		{
			if( version != null )
			{
				var lvTime = Date.fromString( lv.ts );
				var vTime = Date.fromString( version.ts );

				version = lvTime.getTime() > vTime.getTime() ? lv : version;
			}
			else
			{
				version = lv;
			}
		}

		return version;
	}

	public function addLibraries( duell:Array<DuellLib>, haxe:Array<Haxelib>, plugins:Array<DuellLib> )
	{
		var now = Date.now().toString();
		var currentVersion = new LockedVersion( now );

		//create used libs
		for ( dLib in duell )
		{
			var currentCommit = GitHelper.getCurrentCommit( dLib.getPath() );
			var lockedLib = {name:dLib.name, type:'duelllib', version:dLib.version, commitHash:currentCommit};
			currentVersion.addUsedLib( lockedLib );	
		}

		for ( hLib in haxe )
		{
			var lockedLib = {name:hLib.name, type:'haxelib', version:hLib.version, commitHash:''};
			currentVersion.addUsedLib( lockedLib );	
		}

		for ( p in plugins )
		{
			var currentCommit = GitHelper.getCurrentCommit( p.getPath() );
			var lockedLib = {name:p.name, type:'plugin', version:p.version, commitHash:currentCommit};
			currentVersion.addPlugin( lockedLib );		
		}

		var lastLockedVersion = getLastLockedVersion();
		lockedVersions.push( currentVersion );

		//check differences
		checkUpdates( lastLockedVersion, currentVersion );

		checkNumberTrackedVersions();

		saveFile();
	}

	public function getLastLockedLibraries() : LockedLibraries
	{
		var libraries = getLastLockedVersion();
		var usedLibraries = libraries != null ? libraries.usedLibs : new Map<String, LockedLib>();

		var dLibs = new Array<DuellLib>();
    	var hLibs = new Array<Haxelib>();
    	var plugins = new Array<DuellLib>();

    	for ( key in usedLibraries.keys() )
    	{
    		var lockedLib = usedLibraries.get( key );
    		switch( lockedLib.type )
    		{
    			case 'duelllib':
    				 dLibs.push(DuellLib.getDuellLib(lockedLib.name, lockedLib.version, lockedLib.commitHash)); 
    			case 'haxelib':
    				 hLibs.push(Haxelib.getHaxelib(lockedLib.name, lockedLib.version));
    			case 'plugin':
    				 plugins.push(DuellLib.getDuellLib(lockedLib.name, lockedLib.version, lockedLib.commitHash));

			}
    	}

    	return { duelllibs:dLibs, haxelibs:hLibs, plugins:plugins };
	}

	private function checkUpdates( oldVersion:LockedVersion, newVersion:LockedVersion )
	{
		if( oldVersion == null )
			return;

		for ( newLib in newVersion.usedLibs )
		{
			if(!oldVersion.usedLibs.exists( newLib.name ))
			{
				var update = {name:NEW_LIB, oldValue:'0.0.0', newValue:newLib.version};
				newVersion.addUpdatedLib( newLib.name, update );
				continue;
			}

			var oldLib = oldVersion.usedLibs.get( newLib.name );
			if( oldLib.version != newLib.version )
			{
				var update = {name:VERSION, oldValue:oldLib.version, newValue:newLib.version};
				newVersion.addUpdatedLib( newLib.name, update );
			}

			if( oldLib.commitHash != newLib.commitHash )
			{
				var update = {name:COMMITHASH, oldValue:oldLib.commitHash, newValue:newLib.commitHash};
				newVersion.addUpdatedLib( newLib.name, update );	
			}
		}

		for ( oldLib in oldVersion.usedLibs )
		{
			if(!newVersion.usedLibs.exists( oldLib.name ))
			{
				var update = {name:REMOVED_LIB, oldValue:oldLib.version, newValue:'0.0.0'};
				newVersion.addUpdatedLib( oldLib.name, update );
			}
		}
	}

	private function checkNumberTrackedVersions()
	{
		var num = lockedVersions.length - NUMBER_MAX_TRACKED_VERSIONS;
		if( num > 0 )
		{
			lockedVersions.splice(0, num);
		}
	}

	private function saveFile()
	{
		var content = parser.createFileContent( lockedVersions );

		var fileOutput = File.write(path, false);
		fileOutput.writeString( content );
		fileOutput.close();
	}
}
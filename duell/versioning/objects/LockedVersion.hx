package duell.versioning.objects;

enum LibChangeType
{
	VERSION;
	NEW_LIB;
	REMOVED_LIB;
	COMMITHASH;
}

typedef LockedLib = {
	name : String,
	type : String,
	version : String,
	commitHash : String
}

typedef Update = {
	name : LibChangeType,
	oldValue : String,
	newValue : String
}

class LockedVersion
{

	public static function getLibChangeType( value:String ) : LibChangeType
	{
		switch( value ){
			case 'version' : return VERSION;
			case 'commitHash' : return COMMITHASH;
			case 'newLib' : return NEW_LIB;
			case 'removedLib' : return REMOVED_LIB;
		}

		return null;
	}

	public static function getLibChangeTypeAsString( value:LibChangeType ) : String
	{
		switch( value ){
			case VERSION : return 'version';
			case COMMITHASH : return 'commitHash';
			case NEW_LIB : return 'newLib';
			case REMOVED_LIB : return 'removedLib';
		}

		return null;
	}

	public var ts(default, null) : Float;
	public var usedLibs : Map<String, LockedLib>;
	public var updates : Map<String, Array<Update>>;

	public function new( ts:Float )
	{
		this.ts = ts;

		usedLibs = new Map<String, LockedLib>();
		updates = new Map<String, Array<Update>>();
	}

	public function addUsedLib( lib:LockedLib )
	{
		usedLibs.set( lib.name, lib );
	}

	public function addUpdatedLib( libName:String, change:Update )
	{
		if(!updates.exists( libName ))
		{
			updates.set(libName, new Array<Update>());
		}

		var list = updates.get( libName );
		list.push( change );
	}

	public function toString() : String
	{
		return 'Class::LockedVersion:: ts:' + ts + '\nusedLibs:\n...\nupdates:\n...';
	}
}
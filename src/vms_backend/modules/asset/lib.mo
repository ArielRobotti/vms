import Map "mo:map/Map";
import { ihash } "mo:map/Map";
import Types "./types";
import SharedTypes "../sharedTypes";
import { now } "mo:core/Time";
import Array "mo:core/Array";


module {
    public type AssetDB = Types.AssetDB;
    public type AssetMetadata = Types.AssetMetadata;

    public func initState(): AssetDB {
        Map.new<Types.UID, AssetMetadata>()
    };

    public func uploadAsset(db: AssetDB, assetData: Types.AssetMetadata): { #Err : Text; #Ok : SharedTypes.UID } {
        let id = now();
        let newAsset = {
            assetData with
            id
        };
        ignore Map.put(db, ihash, id, newAsset);
        #Ok(id)
    };

    public func get(db: AssetDB, id: Types.UID, caller: Principal): { #Ok: AssetMetadata; #Err: Text } {
        switch (Map.get(db, ihash, id)) {
            case null return #Err("Asset not found");
            case ( ?asset ) {
                switch (asset.access){
                    case ( #OnlyOwner) {
                        if(caller != asset.owner) { return  #Err("Caller is not owner")};
                    };
                    case (#RestrictedTo(users)) {
                        if(Array.find<Principal>(users, func x = x == caller) == null) {
                            return #Err("Denied Access")
                        };
                    };
                    case _ {};
                };
                #Ok(asset)
            }
        }
    };


}
import SharedTypes "../sharedTypes";
import Map "mo:map/Map";

module {

  public type UID = SharedTypes.UID;
  public type AssetId = SharedTypes.UID;
  public type StorageLocation = SharedTypes.StorageLocation;

  public type Access = {
    #Public;
    #RestrictedTo : [Principal];
    #OnlyOwner;
  };

  public type AssetDB = Map.Map<AssetId, AssetMetadata>;

  public type AssetMetadata = {
    id: AssetId;
    title : Text;
    description : Text;
    mimeType : Text;
    duration : Int;
    size : Nat;
    totalChunks : Nat;
    tags : [Text];
    location : StorageLocation;
    extraData : SharedTypes.MetadataArray;
    owner : Principal;
    access : Access;
  };
};

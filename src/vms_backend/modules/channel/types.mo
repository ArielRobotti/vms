import SharedTypes "../sharedTypes";
import Map "mo:map/Map";

module {

  public type  UID = SharedTypes.UID;
  public type AssetId = SharedTypes.UID;

  public type ChannelMap = Map.Map<Principal, Channel>; // Cada usuario estará asociado a un único canal

  public type ChannelDataInit = {
    title : Text;
    description : Text;
  };

  public type Channel = ChannelDataInit and {
    tags: [Text];
    banner : ?Blob;
    logo : ?Blob;
    owner : Principal;
    recoveryEmail : Text;
    content: [AssetId];
    followers : [Principal];
    followeds : [Principal];
    extraData : SharedTypes.MetadataArray;
    visible : Bool;
  };

  public type ChannelEditableData = {
    name: Text;
    description : Text;
    tags: [Text];
    logo : ?Blob;  // 100KiB recomendado
    banner : ?Blob; // Hasta 1MiB recomendado
    visible : Bool;
  };

  public type ChannelPreview = {
    owner : Principal;
    logo: ?Blob;
    title: Text;
    tags: [Text];
    followersQty: Nat;
  };
};

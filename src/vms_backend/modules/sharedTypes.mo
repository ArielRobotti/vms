import List "mo:core/List";
import Map "mo:map/Map";

module {

    public type UID = Int;
    public type Key = Text; 
    public type Value = {
        #Nat : Nat;
        #Int : Int;
        #Text : Text;
        #Principal: Principal;
        #Blob : Blob;
        #Bool : Bool;
        #ArrayNat : [Nat];
        #ArrayText : [Text];
        #ArrayPrincipal : [Principal];
        #ArrayInt : [Int];
        #ArrayBlob : [Blob];
    };
    public type MetadataItem = (Key, Value);
    
    public type MetadataArray = [MetadataItem];
    public type MetadataMap = Map.Map<Text, Value>;


    public type StorageLocation = {
        bucket: Principal;
        internalId: Int;
    };

    public type UserPreview = {
        name: Text;
        principal: Principal;
        avatar: ?Text;
    };





}
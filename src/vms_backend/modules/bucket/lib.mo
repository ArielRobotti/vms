import Types "types";
import Principal "mo:core/Principal";
import Map "mo:map/Map";
import { phash } "mo:map/Map";
import Bucket "Bucket";
import { print } "mo:core/Debug";
import Iter "mo:core/Iter";
import SharedTypes "../sharedTypes";

module {

  //------------------- Types -------------------//
  public type FileDataInput = Types.FileDataInput;
  public type MetadataFile = Types.MetadataFile;
  public type UploadResponse = Types.UploadResponse;

  public type BucketCluster = {
    buckets : Map.Map<Principal, Bucket.Bucket>;
    admin : Principal;
    chunkSize: Nat;
    cyclesForDeploy : Nat;
  };

  //---------------------------- private fuinctions ------------------------------//

  func createBucket(cluster : BucketCluster) : async Principal {
     print("Creando Bucket");
    let newBucket = await (with cycles = cluster.cyclesForDeploy) Bucket.Bucket(cluster.admin);
    let canisterId = Principal.fromActor(newBucket);
    print("Bucket creado en " # debug_show(canisterId));
    ignore Map.put<Principal, Bucket.Bucket>(cluster.buckets, phash, canisterId, newBucket);
    canisterId;
  };

  //------------------------------------------------------------------------------//

  public func initClusterBucket(admin : Principal, cyclesForDeploy : Nat) : BucketCluster {
    {
      buckets = Map.new<Principal, Bucket.Bucket>();
      admin;
      chunkSize = 1024 * 1024;
      cyclesForDeploy;
    };
  };

  public func getBucketFor(cluster : BucketCluster, user : Principal, md : FileDataInput) : async Types.UploadResponse {
    for (bucket in Map.vals(cluster.buckets)) {
      let response = await bucket.requestStorageFor(md, user);
      switch response {
        case (#Ok(locationData)) { return #Ok(locationData) };
        case (#Err(e)) {return #Err(e)};
        case _ {}
      };
    };
    let newBucketCanisterId = await createBucket(cluster);
    let newBucketActor : Bucket.Bucket = actor (Principal.toText(newBucketCanisterId));
    await newBucketActor.requestStorageFor(md, user);
  };

  public func checkAssetReady(cluster: BucketCluster, location: SharedTypes.StorageLocation): async Bool {
    switch(Map.get(cluster.buckets, phash, location.bucket)) {
        case null false;
        case ( ?bucket ) {
            await bucket.isFileReady(location. internalId)
        }
    };
  };

  public func addBucketController(bucketId: Principal, controller: Principal): async () {
    await Types.addController(bucketId, controller)
  };

  public func balance(bucketId: Principal): async Nat {
    await Types.balance(bucketId)
  };

  //-------------------------------------------------//
  public func getBucketList(cluster : BucketCluster): [Principal] {
    Iter.toArray<Principal>(Map.keys<Principal, Bucket.Bucket>(cluster.buckets))
  }

};

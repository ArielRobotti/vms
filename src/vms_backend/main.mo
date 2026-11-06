import Types "./types";
import User "./modules/user";
import Channel "./modules/channel";
import Asset "./modules/asset";
import Storage "./modules/bucket";


shared ({caller = DEPLOYER}) persistent actor class() = this  {

  //----------------- state variables -----------------//

  let _config = {
    var cyclesForDeploy: Nat = 2_000_000_000_000;
  };

  let userDB = User.initState(DEPLOYER);
  let channelDB = Channel.initState();
  let assetDB = Asset.initState();
  let bucketCluster = Storage.initClusterBucket(DEPLOYER, _config.cyclesForDeploy);

  //----------------- Session functions ---------------//
  
  public shared ({ caller }) func signUp({name: Text; email: Text}): async User.SignupResponse {
    User.signUp(userDB, caller, name, email)
  };

  public shared ({ caller }) func login(): async Types.LoginResponse {
    switch(User.login(userDB, caller)) {
      case (#Err(e)) #Err(e);
      case (#Ok(user)) {
        #Ok({
          user
          // Agregar datos de inicio de sesion como notificaciones etc
        })
      }
    }
  };

  public shared ({ caller }) func setEmail(email: Text): async User.LoginResponse {
    User.setEmail(userDB, caller, email)
  };

  public shared ({ caller }) func getCodeVerification(email: Text): async Text {
    User.generateCodeVerification(userDB, caller, email)
  };

  public shared ({ caller }) func verifyEmail(code: Text): async Bool {
    User.validateCode(userDB, caller, code)
  };

  //---------------- Channel CRUD ---------------------//

  public shared ({ caller }) func createChannel(init : Channel.ChannelDataInit): async {#Ok: Channel.Channel; #Err: Text} {
    assert(User.isUser(userDB, caller));
    switch(User.getVerifiedEmail(userDB, caller)){
      case null #Err("Email not verificated");
      case (?email) {
        #Ok(Channel.createChannel(channelDB, caller, email, init))
      }
    }
  };

  public shared ({ caller }) func getChannel(owner: ?Principal): async {#Ok: Channel.Channel; #Err: Text} {
    let targetOwner = switch(owner){
      case null caller;
      case ( ?owner ) { owner }
    };
    Channel.getChannel(channelDB, targetOwner)
  };
  
  public shared ({ caller }) func editChannel(data: Channel.ChannelEditableData): async {#Ok: Channel.Channel; #Err: Text}{
    assert(User.isUser(userDB, caller));
    Channel.editChannel(channelDB, caller, data)
  };

  //----------------  Assets upload managment -----------------//

  public shared ({ caller }) func getStorageFor({info: Storage.FileDataInput}): async Storage.UploadResponse {
    if( not User.isUser(userDB, caller) ) {
      return #Err("Caller is not user");
    };
    if( not Channel.channelExist(channelDB, caller)) {
      return #Err("Caller does not have an associated channel");
    };
    await Storage.getBucketFor(bucketCluster, caller, info)
  };

  public shared ({ caller }) func registerAsset(newAssetData: Asset.AssetMetadata): async {#Ok: Int; #Err: Text} {
    if( not User.isUser(userDB, caller) ) {
      return #Err("Caller is not user")
    };
    let channel = Channel.getChannel(channelDB, caller);
    switch channel {
      case (#Err(e)) { return #Err(e) };
      case (#Ok(channel)) {
        let assetReady = await Storage.checkAssetReady(bucketCluster, newAssetData.location);
        if( not assetReady) {
          return #Err("Asset not ready") 
        };
        let uploadResult = Asset.uploadAsset(assetDB, newAssetData);
        switch uploadResult {
          case (#Ok(id)) {
            Channel.addAsset(channelDB, caller, id)
          };
          case _ { 
            uploadResult 
          }
        };
      }
    };
  };

  public shared query ({ caller }) func getAssetPreview(id: Int): async {#Ok: Asset.AssetMetadata; #Err: Text} {
    Asset.get(assetDB, id, caller)
  };

  
};

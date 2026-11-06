import SharedTypes "../sharedTypes";
import Map "mo:map/Map";
import Set "mo:map/Set";
import List "mo:core/List";


module  {

    public type UserDB = {
        temporalCodes: Map.Map<Principal, CodeVerification>;
        timeoutCodeVerification: Int;
        users : Map.Map<Principal, User>;
        admins : Set.Set<Principal>;
        blackList: Set.Set<Text>; // Principals y/o emails
    };
    
    public type UserDataInit = {
        email: Text; // Requiere verificación. Enviar temporalCode via email (HTTP Outcals) y validar
        name: Text;  
    };

    public type CodeVerification = {
        code: Text; // Codigo de seis digitos de 100000 a 999999 derivado del Timestamp
        generatedAt: Int; // Timestamp para validar timeout
    };

    public type User = UserDataInit and {
        principal: Principal;
        signUpDate: Int;
        metadataUser: SharedTypes.MetadataArray;
        preferences: SharedTypes.MetadataArray;
        verificated: Bool;
        avatar: ?Blob;
    };

    public type UserDataInfo = {
        avatar: ?Blob;
        name: Text;
        email: Text;
        principal: Principal;
        verificated: Bool;
    };

    public type UserPreview = {
        principal: Principal;
        name: Text;
        verificated: Bool;
        signUpDate: Int;
        avatar: ?Blob;
    };


    public type ErrorCaller = {
        #AnonymousCaller;
        #CallerInBlackList;
        #CallerIsAlreadyUser;
    };

    public type ErrorEmail = {
        #EmailInBlackList;
        #EmailIsAlreadyRegistered; // Asociar a un valor identificatorio del usuario existente
    };
    public type ErrorSignup = ErrorCaller or ErrorEmail or {
        #IncorrectCode;
        #CodeNotGenerated;
        #TimeoutError;
    };

    public type SignupResponse = {
        #Ok: User;
        #Err: ErrorSignup
    };

    public type LoginResponse = {
        #Ok : User;
        #Err : Text;
    };

    

    
    

    






}

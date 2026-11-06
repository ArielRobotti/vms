import User "./modules/user"

module {
    public type LoginResponse = {
        #Ok: {
            user: User.User;
        };
        #Err: Text
    }

}
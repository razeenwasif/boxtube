import { createContext, useState, useContext, useEffect } from 'react';

// Create the authentication context
const AuthContext = createContext();

// Local storage key
const AUTH_KEY = 'boxtube_auth';
const USERS_KEY = 'boxtube_users';

// Provider component that wraps the app and makes auth available to any child component
export function AuthProvider({ children }) {
  const [currentUser, setCurrentUser] = useState(null);
  const [loading, setLoading] = useState(true);
  
  // Load auth state from localStorage on mount
  useEffect(() => {
    const loadAuth = () => {
      try {
        const savedAuth = localStorage.getItem(AUTH_KEY);
        if (savedAuth) {
          setCurrentUser(JSON.parse(savedAuth));
        }
      } catch (error) {
        console.error('Error loading auth state:', error);
      } finally {
        setLoading(false);
      }
    };
    
    loadAuth();
  }, []);
  
  // Get all users
  const getUsers = () => {
    try {
      const savedUsers = localStorage.getItem(USERS_KEY);
      return savedUsers ? JSON.parse(savedUsers) : [];
    } catch (error) {
      console.error('Error getting users:', error);
      return [];
    }
  };
  
  // Save users
  const saveUsers = (users) => {
    try {
      localStorage.setItem(USERS_KEY, JSON.stringify(users));
    } catch (error) {
      console.error('Error saving users:', error);
    }
  };
  
  // Sign up
  const signup = (username, password) => {
    return new Promise((resolve, reject) => {
      try {
        // Get existing users
        const users = getUsers();
        
        // Check if username already exists
        if (users.some(user => user.username.toLowerCase() === username.toLowerCase())) {
          reject(new Error('Username already exists'));
          return;
        }
        
        // Create new user
        const newUser = {
          id: `user-${Date.now()}`,
          username,
          password, // In a real app, this should be hashed
          createdAt: new Date().toISOString(),
          subscriptions: [],
          watchHistory: [],
          profilePicture: `https://ui-avatars.com/api/?name=${encodeURIComponent(username)}&background=random&color=fff`
        };
        
        // Add user to users list
        users.push(newUser);
        saveUsers(users);
        
        // Set current user
        setCurrentUser(newUser);
        localStorage.setItem(AUTH_KEY, JSON.stringify(newUser));
        
        resolve(newUser);
      } catch (error) {
        reject(error);
      }
    });
  };
  
  // Log in
  const login = (username, password) => {
    return new Promise((resolve, reject) => {
      try {
        // Get users
        const users = getUsers();
        
        // Find user with matching username and password
        const user = users.find(u => 
          u.username.toLowerCase() === username.toLowerCase() && 
          u.password === password
        );
        
        if (!user) {
          reject(new Error('Invalid username or password'));
          return;
        }
        
        // Set current user
        setCurrentUser(user);
        localStorage.setItem(AUTH_KEY, JSON.stringify(user));
        
        resolve(user);
      } catch (error) {
        reject(error);
      }
    });
  };
  
  // Log out
  const logout = () => {
    setCurrentUser(null);
    localStorage.removeItem(AUTH_KEY);
  };
  
  // Update profile
  const updateProfile = (updates) => {
    return new Promise((resolve, reject) => {
      try {
        // Get users
        const users = getUsers();
        
        // Find and update user
        const updatedUsers = users.map(user => {
          if (user.id === currentUser.id) {
            const updatedUser = {
              ...user,
              ...updates,
              // Don't allow updating these fields
              id: user.id,
              createdAt: user.createdAt
            };
            
            // Update current user
            setCurrentUser(updatedUser);
            localStorage.setItem(AUTH_KEY, JSON.stringify(updatedUser));
            
            return updatedUser;
          }
          return user;
        });
        
        // Save updated users
        saveUsers(updatedUsers);
        
        resolve();
      } catch (error) {
        reject(error);
      }
    });
  };
  
  // Subscribe to channel
  const subscribeToChannel = (channelId, channelTitle, channelThumbnail) => {
    if (!currentUser) return false;
    
    try {
      const isSubscribed = currentUser.subscriptions?.some(sub => sub.channelId === channelId);
      
      let updatedSubscriptions;
      if (isSubscribed) {
        // Unsubscribe
        updatedSubscriptions = currentUser.subscriptions.filter(sub => sub.channelId !== channelId);
      } else {
        // Subscribe
        const newSubscription = {
          channelId,
          channelTitle,
          channelThumbnail,
          subscribedAt: new Date().toISOString()
        };
        updatedSubscriptions = [...(currentUser.subscriptions || []), newSubscription];
      }
      
      // Update user
      updateProfile({ subscriptions: updatedSubscriptions });
      
      return !isSubscribed;
    } catch (error) {
      console.error('Error updating subscription:', error);
      return false;
    }
  };
  
  // Check if subscribed to channel
  const isSubscribed = (channelId) => {
    if (!currentUser) return false;
    return currentUser.subscriptions?.some(sub => sub.channelId === channelId) || false;
  };
  
  const value = {
    currentUser,
    signup,
    login,
    logout,
    updateProfile,
    subscribeToChannel,
    isSubscribed,
    loading
  };
  
  return (
    <AuthContext.Provider value={value}>
      {!loading && children}
    </AuthContext.Provider>
  );
}

// Custom hook to use the auth context
export function useAuth() {
  return useContext(AuthContext);
} 
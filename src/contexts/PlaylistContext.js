import { createContext, useState, useContext, useEffect } from 'react';
import { useAuth } from './AuthContext';

// Create the playlist context
const PlaylistContext = createContext();

// Local storage key
const PLAYLISTS_KEY = 'boxtube_playlists';

// Provider component that wraps the app and makes playlists available
export function PlaylistProvider({ children }) {
  const [playlists, setPlaylists] = useState([]);
  const { currentUser } = useAuth();
  
  // Load playlists from localStorage on mount or user change
  useEffect(() => {
    const loadPlaylists = () => {
      try {
        // If user is logged in, use user-specific key
        const storageKey = currentUser 
          ? `${PLAYLISTS_KEY}_${currentUser.id}` 
          : PLAYLISTS_KEY;
          
        const savedPlaylists = localStorage.getItem(storageKey);
        if (savedPlaylists) {
          setPlaylists(JSON.parse(savedPlaylists));
        } else {
          // Initialize with default playlists if none exist
          const defaultPlaylists = [
            {
              id: 'watch-later',
              name: 'Watch Later',
              description: 'Videos to watch later',
              videos: [],
              createdAt: new Date().toISOString(),
              isDefault: true
            },
            {
              id: 'favorites',
              name: 'Favorites',
              description: 'Your favorite videos',
              videos: [],
              createdAt: new Date().toISOString(),
              isDefault: true
            }
          ];
          
          setPlaylists(defaultPlaylists);
          localStorage.setItem(storageKey, JSON.stringify(defaultPlaylists));
        }
      } catch (error) {
        console.error('Error loading playlists:', error);
        // Reset if there's an error
        setPlaylists([]);
      }
    };
    
    loadPlaylists();
  }, [currentUser]);
  
  // Save playlists to localStorage whenever they change
  useEffect(() => {
    if (playlists.length > 0) {
      try {
        // If user is logged in, use user-specific key
        const storageKey = currentUser 
          ? `${PLAYLISTS_KEY}_${currentUser.id}` 
          : PLAYLISTS_KEY;
          
        localStorage.setItem(storageKey, JSON.stringify(playlists));
      } catch (error) {
        console.error('Error saving playlists:', error);
      }
    }
  }, [playlists, currentUser]);
  
  // Create a new playlist
  const createPlaylist = (name, description = '') => {
    const newPlaylist = {
      id: `playlist-${Date.now()}`,
      name,
      description,
      videos: [],
      createdAt: new Date().toISOString(),
      isDefault: false
    };
    
    setPlaylists(prevPlaylists => [...prevPlaylists, newPlaylist]);
    return newPlaylist;
  };
  
  // Delete a playlist
  const deletePlaylist = (playlistId) => {
    // Don't allow deleting default playlists
    const playlist = playlists.find(p => p.id === playlistId);
    if (playlist?.isDefault) {
      return false;
    }
    
    setPlaylists(prevPlaylists => 
      prevPlaylists.filter(playlist => playlist.id !== playlistId)
    );
    
    return true;
  };
  
  // Update playlist details
  const updatePlaylist = (playlistId, updates) => {
    setPlaylists(prevPlaylists => 
      prevPlaylists.map(playlist => {
        if (playlist.id === playlistId) {
          return { 
            ...playlist, 
            ...updates,
            // Don't allow changing isDefault status
            isDefault: playlist.isDefault
          };
        }
        return playlist;
      })
    );
  };
  
  // Add a video to a playlist
  const addToPlaylist = (playlistId, video) => {
    // Normalize the video ID
    const videoId = video.id?.videoId || video.id;
    
    setPlaylists(prevPlaylists => 
      prevPlaylists.map(playlist => {
        if (playlist.id === playlistId) {
          // Check if video already exists in playlist
          const videoExists = playlist.videos.some(v => {
            const existingVideoId = v.id?.videoId || v.id;
            return existingVideoId === videoId;
          });
          
          if (videoExists) {
            return playlist;
          }
          
          return {
            ...playlist,
            videos: [
              ...playlist.videos,
              {
                ...video,
                addedAt: new Date().toISOString()
              }
            ]
          };
        }
        return playlist;
      })
    );
  };
  
  // Remove a video from a playlist
  const removeFromPlaylist = (playlistId, videoId) => {
    setPlaylists(prevPlaylists => 
      prevPlaylists.map(playlist => {
        if (playlist.id === playlistId) {
          return {
            ...playlist,
            videos: playlist.videos.filter(video => {
              const existingVideoId = video.id?.videoId || video.id;
              return existingVideoId !== videoId;
            })
          };
        }
        return playlist;
      })
    );
  };
  
  // Check if a video is in a playlist
  const isInPlaylist = (playlistId, videoId) => {
    const playlist = playlists.find(p => p.id === playlistId);
    if (!playlist) return false;
    
    return playlist.videos.some(video => {
      const existingVideoId = video.id?.videoId || video.id;
      return existingVideoId === videoId;
    });
  };
  
  // Get a playlist by ID
  const getPlaylist = (playlistId) => {
    return playlists.find(playlist => playlist.id === playlistId) || null;
  };
  
  // Get all playlists
  const getAllPlaylists = () => {
    return playlists;
  };
  
  // Context value
  const value = {
    playlists,
    createPlaylist,
    deletePlaylist,
    updatePlaylist,
    addToPlaylist,
    removeFromPlaylist,
    isInPlaylist,
    getPlaylist,
    getAllPlaylists
  };
  
  return (
    <PlaylistContext.Provider value={value}>
      {children}
    </PlaylistContext.Provider>
  );
}

// Custom hook to use the playlist context
export function usePlaylist() {
  return useContext(PlaylistContext);
} 
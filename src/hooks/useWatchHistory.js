import { useState, useEffect, useCallback } from 'react';

const WATCH_HISTORY_KEY = 'boxtube_watch_history';
const MAX_HISTORY_ITEMS = 100;

/**
 * Custom hook for managing watch history
 * @returns {Object} Watch history state and functions
 */
const useWatchHistory = () => {
  const [watchHistory, setWatchHistory] = useState([]);

  // Load watch history from localStorage on mount
  useEffect(() => {
    const savedHistory = localStorage.getItem(WATCH_HISTORY_KEY);
    if (savedHistory) {
      try {
        setWatchHistory(JSON.parse(savedHistory));
      } catch (error) {
        console.error('Error loading watch history:', error);
        localStorage.removeItem(WATCH_HISTORY_KEY);
      }
    }
  }, []);

  // Save watch history to localStorage whenever it changes
  useEffect(() => {
    localStorage.setItem(WATCH_HISTORY_KEY, JSON.stringify(watchHistory));
  }, [watchHistory]);

  // Add a video to watch history
  const addToHistory = useCallback((video) => {
    setWatchHistory(prevHistory => {
      // Remove the video if it already exists
      const filteredHistory = prevHistory.filter(item => item.id.videoId !== video.id.videoId);
      
      // Add the video to the beginning of the array
      const newHistory = [video, ...filteredHistory];
      
      // Limit the history size
      return newHistory.slice(0, MAX_HISTORY_ITEMS);
    });
  }, []);

  // Clear watch history
  const clearHistory = useCallback(() => {
    setWatchHistory([]);
    localStorage.removeItem(WATCH_HISTORY_KEY);
  }, []);

  // Check if a video is in watch history
  const isWatched = useCallback((videoId) => {
    return watchHistory.some(item => item.id.videoId === videoId);
  }, [watchHistory]);

  return {
    watchHistory,
    addToHistory,
    clearHistory,
    isWatched
  };
};

export default useWatchHistory; 
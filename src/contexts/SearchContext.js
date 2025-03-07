import { createContext, useState, useContext, useEffect } from 'react';
import { useAuth } from './AuthContext';

// Create the search context
const SearchContext = createContext();

// Local storage key
const SEARCH_HISTORY_KEY = 'boxtube_search_history';
const MAX_HISTORY_ITEMS = 20;

// Provider component that wraps the app and makes search history available
export function SearchProvider({ children }) {
  const [searchHistory, setSearchHistory] = useState([]);
  const [suggestions, setSuggestions] = useState([]);
  const { currentUser } = useAuth();
  
  // Load search history from localStorage on mount or user change
  useEffect(() => {
    const loadSearchHistory = () => {
      try {
        // If user is logged in, use user-specific key
        const storageKey = currentUser 
          ? `${SEARCH_HISTORY_KEY}_${currentUser.id}` 
          : SEARCH_HISTORY_KEY;
          
        const savedHistory = localStorage.getItem(storageKey);
        if (savedHistory) {
          setSearchHistory(JSON.parse(savedHistory));
        }
      } catch (error) {
        console.error('Error loading search history:', error);
        // Reset if there's an error
        setSearchHistory([]);
      }
    };
    
    loadSearchHistory();
  }, [currentUser]);
  
  // Save search history to localStorage whenever it changes
  useEffect(() => {
    if (searchHistory.length > 0) {
      try {
        // If user is logged in, use user-specific key
        const storageKey = currentUser 
          ? `${SEARCH_HISTORY_KEY}_${currentUser.id}` 
          : SEARCH_HISTORY_KEY;
          
        localStorage.setItem(storageKey, JSON.stringify(searchHistory));
      } catch (error) {
        console.error('Error saving search history:', error);
      }
    }
  }, [searchHistory, currentUser]);
  
  // Add a search term to history
  const addToSearchHistory = (term) => {
    if (!term || term.trim() === '') return;
    
    const trimmedTerm = term.trim();
    
    setSearchHistory(prevHistory => {
      // Remove the term if it already exists
      const filteredHistory = prevHistory.filter(item => 
        item.term.toLowerCase() !== trimmedTerm.toLowerCase()
      );
      
      // Add the new term at the beginning
      const newHistory = [
        { 
          term: trimmedTerm, 
          timestamp: new Date().toISOString() 
        },
        ...filteredHistory
      ].slice(0, MAX_HISTORY_ITEMS); // Limit to max items
      
      return newHistory;
    });
  };
  
  // Clear search history
  const clearSearchHistory = () => {
    setSearchHistory([]);
    
    // Clear from localStorage
    const storageKey = currentUser 
      ? `${SEARCH_HISTORY_KEY}_${currentUser.id}` 
      : SEARCH_HISTORY_KEY;
      
    localStorage.removeItem(storageKey);
  };
  
  // Remove a single search term from history
  const removeFromSearchHistory = (term) => {
    setSearchHistory(prevHistory => 
      prevHistory.filter(item => item.term !== term)
    );
  };
  
  // Generate suggestions based on search history and input
  const getSuggestions = (input) => {
    if (!input || input.trim() === '') {
      setSuggestions([]);
      return [];
    }
    
    const inputLower = input.toLowerCase().trim();
    
    // Filter history items that start with or contain the input
    const historyMatches = searchHistory
      .filter(item => item.term.toLowerCase().includes(inputLower))
      .map(item => item.term)
      .slice(0, 5); // Limit to 5 history suggestions
    
    // Add some trending/popular searches if we have few history matches
    const trendingSuggestions = [
      'music videos',
      'trending',
      'news today',
      'gaming',
      'tutorials',
      'documentaries',
      'podcasts',
      'live streams'
    ];
    
    // Filter trending suggestions that match input
    const trendingMatches = trendingSuggestions
      .filter(term => term.toLowerCase().includes(inputLower))
      .slice(0, 3); // Limit to 3 trending suggestions
    
    // Combine history and trending matches, removing duplicates
    const allSuggestions = [...new Set([...historyMatches, ...trendingMatches])].slice(0, 8);
    
    setSuggestions(allSuggestions);
    return allSuggestions;
  };
  
  // Get recent searches (last 5)
  const getRecentSearches = () => {
    return searchHistory.slice(0, 5).map(item => item.term);
  };
  
  // Context value
  const value = {
    searchHistory,
    suggestions,
    addToSearchHistory,
    clearSearchHistory,
    removeFromSearchHistory,
    getSuggestions,
    getRecentSearches
  };
  
  return (
    <SearchContext.Provider value={value}>
      {children}
    </SearchContext.Provider>
  );
}

// Custom hook to use the search context
export function useSearch() {
  return useContext(SearchContext);
} 
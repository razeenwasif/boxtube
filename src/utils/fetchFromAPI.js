// this is the utility function for fetching API data
import axios from 'axios';

const BASE_URL = 'https://youtube-v31.p.rapidapi.com';

// Cache for API responses
const apiCache = new Map();
const CACHE_DURATION = 5 * 60 * 1000; // 5 minutes in milliseconds

// Check if API key is available
const RAPID_API_KEY = process.env.REACT_APP_RAPID_API_KEY;

if (!RAPID_API_KEY) {
  console.error('YouTube API key is not set. Please set REACT_APP_RAPID_API_KEY in your environment variables.');
}

const options = {
  params: {
    maxResults: '50'
  },
  headers: {
    'X-RapidAPI-Key': RAPID_API_KEY,
    'X-RapidAPI-Host': 'youtube-v31.p.rapidapi.com'
  }
};

/**
 * Generates a cache key from the URL and any additional parameters
 */
const generateCacheKey = (url, params = {}) => {
  return `${url}:${JSON.stringify(params)}`;
};

/**
 * Checks if a cached response is still valid
 */
const isCacheValid = (cacheEntry) => {
  return cacheEntry && (Date.now() - cacheEntry.timestamp) < CACHE_DURATION;
};

/* This is the function tha allows us to call the API, pass some dynamic url and 
   then call it from within any component within the application */

// async function accepts only one parameter which is the url
export const fetchFromAPI = async (url, additionalParams = {}) => {
  try {
    if (!RAPID_API_KEY) {
      throw new Error('YouTube API key is not configured. Please add your RapidAPI key to the .env file.');
    }

    // Generate cache key
    const cacheKey = generateCacheKey(url, additionalParams);
    
    // Check cache first
    const cachedResponse = apiCache.get(cacheKey);
    if (isCacheValid(cachedResponse)) {
      console.log('Returning cached response for:', url);
      return cachedResponse.data;
    }

    // Merge additional parameters with default options
    const requestOptions = {
      ...options,
      params: {
        ...options.params,
        ...additionalParams
      }
    };

    // Log the request details (remove in production)
    console.log('Making API request to:', `${BASE_URL}/${url}`);
    console.log('With options:', {
      ...requestOptions,
      headers: {
        ...requestOptions.headers,
        'X-RapidAPI-Key': 'HIDDEN' // Don't log the actual key
      }
    });

    // Make the API request
    const response = await axios.get(`${BASE_URL}/${url}`, requestOptions);
    
    // Validate response
    if (!response.data) {
      throw new Error('No data received from the API');
    }

    // Cache the response
    apiCache.set(cacheKey, {
      data: response.data,
      timestamp: Date.now()
    });

    // Log the response status and structure (remove in production)
    console.log('API Response status:', response.status);
    console.log('API Response structure:', {
      hasData: !!response.data,
      hasItems: !!response.data?.items,
      itemCount: response.data?.items?.length || 0
    });

    return response.data;
  } catch (error) {
    console.error('Error fetching from YouTube API:', error);
    
    if (error.response) {
      console.log('Error response status:', error.response.status);
      console.log('Error response data:', error.response.data);

      switch (error.response.status) {
        case 429:
          throw new Error('API rate limit exceeded. Please try again later.');
        case 403:
          throw new Error('API key is invalid or expired. Please check your RapidAPI key.');
        case 401:
          throw new Error('Unauthorized. Please check if your RapidAPI key is valid.');
        default:
          throw new Error(`API Error: ${error.response.data.message || 'Unknown error occurred'}`);
      }
    } else if (error.request) {
      throw new Error('No response from server. Please check your internet connection.');
    } else {
      throw new Error(error.message);
    }
  }
};
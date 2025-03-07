import { useState, useEffect, useCallback } from 'react';
import { fetchFromAPI } from '../utils/fetchFromAPI';

/**
 * Custom hook for making YouTube API calls with pagination support
 * @param {string} endpoint - API endpoint
 * @param {Object} params - Additional query parameters
 * @returns {Object} API response data, loading state, error state, and pagination functions
 */
const useYoutubeApi = (endpoint, params = {}) => {
  const [data, setData] = useState(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState(null);
  const [pageToken, setPageToken] = useState('');
  const [hasMore, setHasMore] = useState(true);

  // Helper function to fetch video details (duration, statistics)
  const fetchVideoDetails = async (videoIds) => {
    try {
      const response = await fetchFromAPI('videos', {
        part: 'contentDetails,statistics',
        id: videoIds.join(',')
      });

      return response.items.reduce((acc, item) => {
        acc[item.id] = {
          duration: item.contentDetails.duration,
          viewCount: item.statistics.viewCount,
          likeCount: item.statistics.likeCount
        };
        return acc;
      }, {});
    } catch (err) {
      console.error('Error fetching video details:', err);
      return {};
    }
  };

  // Helper function to format duration from ISO 8601
  const formatDuration = (duration) => {
    const match = duration.match(/PT(\d+H)?(\d+M)?(\d+S)?/);
    const hours = (match[1] || '').replace('H', '');
    const minutes = (match[2] || '').replace('M', '');
    const seconds = (match[3] || '').replace('S', '');

    let result = '';
    if (hours) result += `${hours}:`;
    if (minutes) result += `${minutes.padStart(2, '0')}:`;
    else if (hours) result += '00:';
    result += seconds.padStart(2, '0');
    
    return result;
  };

  const fetchData = useCallback(async (nextPageToken = '') => {
    try {
      setError(null);
      if (!nextPageToken) setLoading(true);

      const response = await fetchFromAPI(endpoint, {
        ...params,
        pageToken: nextPageToken
      });

      if (!response?.items) {
        throw new Error('Invalid response from server');
      }

      // Get video IDs for fetching additional details
      const videoIds = response.items
        .filter(item => item.id.videoId)
        .map(item => item.id.videoId);

      // Fetch additional details if there are video IDs
      const videoDetails = videoIds.length > 0 ? await fetchVideoDetails(videoIds) : {};

      // Enhance items with additional details
      const enhancedItems = response.items.map(item => {
        if (item.id.videoId && videoDetails[item.id.videoId]) {
          return {
            ...item,
            contentDetails: {
              duration: formatDuration(videoDetails[item.id.videoId].duration)
            },
            statistics: {
              viewCount: videoDetails[item.id.videoId].viewCount,
              likeCount: videoDetails[item.id.videoId].likeCount
            }
          };
        }
        return item;
      });

      // Update page token and hasMore flag
      setPageToken(response.nextPageToken || '');
      setHasMore(!!response.nextPageToken);

      // Append new items to existing data or set as initial data
      setData(prevData => {
        if (nextPageToken && prevData) {
          return [...prevData, ...enhancedItems];
        }
        return enhancedItems;
      });
    } catch (err) {
      setError(err.message);
      if (!nextPageToken) setData(null);
    } finally {
      setLoading(false);
    }
  }, [endpoint, JSON.stringify(params)]);

  // Initial data fetch
  useEffect(() => {
    let isMounted = true;

    const initFetch = async () => {
      if (!endpoint) {
        setLoading(false);
        setData(null);
        return;
      }

      try {
        setLoading(true);
        setError(null);
        await fetchData();
      } catch (err) {
        if (isMounted) {
          setError(err.message);
          setData(null);
        }
      } finally {
        if (isMounted) {
          setLoading(false);
        }
      }
    };

    initFetch();

    return () => {
      isMounted = false;
    };
  }, [endpoint, JSON.stringify(params)]);

  // Function to fetch more data (for infinite scroll)
  const fetchMoreData = useCallback(async () => {
    if (!hasMore || !pageToken || loading) return;
    await fetchData(pageToken);
  }, [fetchData, hasMore, pageToken, loading]);

  return {
    data,
    loading,
    error,
    hasMore,
    fetchMoreData
  };
};

export default useYoutubeApi; 
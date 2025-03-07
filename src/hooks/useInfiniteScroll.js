import { useState, useEffect, useCallback } from 'react';

/**
 * Custom hook for implementing infinite scrolling
 * @param {Function} fetchMore - Function to fetch more data
 * @param {boolean} hasMore - Whether there is more data to load
 * @param {number} threshold - Distance from bottom to trigger next load (in pixels)
 * @returns {Object} Infinite scroll state and ref
 */
const useInfiniteScroll = (fetchMore, hasMore = true, threshold = 100) => {
  const [isFetching, setIsFetching] = useState(false);
  const [containerRef, setContainerRef] = useState(null);

  const handleScroll = useCallback(() => {
    if (!containerRef || isFetching || !hasMore) return;

    const { scrollTop, scrollHeight, clientHeight } = containerRef;
    const scrolledToBottom = scrollHeight - (scrollTop + clientHeight) <= threshold;

    if (scrolledToBottom) {
      setIsFetching(true);
    }
  }, [containerRef, isFetching, hasMore, threshold]);

  useEffect(() => {
    const currentRef = containerRef;
    if (currentRef) {
      currentRef.addEventListener('scroll', handleScroll);
    }

    return () => {
      if (currentRef) {
        currentRef.removeEventListener('scroll', handleScroll);
      }
    };
  }, [containerRef, handleScroll]);

  useEffect(() => {
    if (!isFetching) return;

    const loadMore = async () => {
      try {
        await fetchMore();
      } finally {
        setIsFetching(false);
      }
    };

    loadMore();
  }, [isFetching, fetchMore]);

  return {
    isFetching,
    setContainerRef,
    containerRef
  };
};

export default useInfiniteScroll; 
import { Box, Typography, Chip, Stack } from '@mui/material';
import { Videos } from './';
import { useParams, useLocation } from 'react-router-dom';
import LoadingState from './common/LoadingState';
import useYoutubeApi from '../hooks/useYoutubeApi';
import { FilterAlt, Clear } from '@mui/icons-material';
import { useNavigate } from 'react-router-dom';

// Helper function to get human-readable filter labels
const getFilterLabel = (key) => {
  const labels = {
    duration: 'Duration',
    uploadDate: 'Upload Date',
    quality: 'Quality',
    language: 'Language',
    sortBy: 'Sort By'
  };
  return labels[key] || key;
};

// Helper function to get human-readable value labels
const getValueLabel = (key, value) => {
  const valueLabels = {
    duration: {
      'short': 'Under 4 minutes',
      'medium': '4-20 minutes',
      'long': 'Over 20 minutes'
    },
    uploadDate: {
      'hour': 'Last hour',
      'day': 'Today',
      'week': 'This week',
      'month': 'This month',
      'year': 'This year'
    },
    quality: {
      'hd': 'HD',
      '4k': '4K'
    },
    language: {
      'en': 'English',
      'es': 'Spanish',
      'fr': 'French',
      'de': 'German',
      'ja': 'Japanese',
      'ko': 'Korean',
      'zh': 'Chinese'
    },
    sortBy: {
      'relevance': 'Relevance',
      'date': 'Upload date',
      'viewCount': 'View count',
      'rating': 'Rating'
    }
  };
  
  return valueLabels[key]?.[value] || value;
};

const SearchFeed = () => {
  const { searchTerm } = useParams();
  const location = useLocation();
  const navigate = useNavigate();
  
  // Parse query parameters
  const queryParams = new URLSearchParams(location.search);
  const activeFilters = [];
  
  // Extract filters from URL
  for (const [key, value] of queryParams.entries()) {
    if (value !== 'any') {
      activeFilters.push({
        key,
        value,
        label: `${getFilterLabel(key)}: ${getValueLabel(key, value)}`
      });
    }
  }
  
  // Build API parameters
  const apiParams = {
    part: 'snippet',
    q: searchTerm,
    maxResults: 50
  };
  
  // Add filters to API parameters
  activeFilters.forEach(filter => {
    // Map our filter keys to YouTube API parameters
    switch (filter.key) {
      case 'duration':
        apiParams.videoDuration = filter.value;
        break;
      case 'uploadDate':
        // Convert our date filters to YouTube's publishedAfter parameter
        const now = new Date();
        let date = new Date();
        
        switch (filter.value) {
          case 'hour':
            date.setHours(now.getHours() - 1);
            break;
          case 'day':
            date.setDate(now.getDate() - 1);
            break;
          case 'week':
            date.setDate(now.getDate() - 7);
            break;
          case 'month':
            date.setMonth(now.getMonth() - 1);
            break;
          case 'year':
            date.setFullYear(now.getFullYear() - 1);
            break;
          default:
            // If unknown value, default to last week
            date.setDate(now.getDate() - 7);
            break;
        }
        
        apiParams.publishedAfter = date.toISOString();
        break;
      case 'quality':
        apiParams.videoDefinition = filter.value === '4k' ? 'high' : filter.value;
        break;
      case 'language':
        apiParams.relevanceLanguage = filter.value;
        break;
      case 'sortBy':
        apiParams.order = filter.value;
        break;
      default:
        // For any unknown filter keys, we'll just ignore them
        console.warn(`Unknown filter key: ${filter.key}`);
        break;
    }
  });
  
  // Add video type filter
  apiParams.type = 'video';
  
  const { 
    data: videos, 
    loading, 
    error, 
    hasMore, 
    fetchMoreData 
  } = useYoutubeApi(
    searchTerm ? 'search' : null,
    apiParams
  );
  
  // Remove a filter and navigate to updated URL
  const removeFilter = (filterKey) => {
    const newParams = new URLSearchParams(location.search);
    newParams.delete(filterKey);
    
    navigate(`/search/${searchTerm}${newParams.toString() ? `?${newParams.toString()}` : ''}`);
  };
  
  // Clear all filters
  const clearAllFilters = () => {
    navigate(`/search/${searchTerm}`);
  };

  // Show initial loading state
  if (loading && !videos) {
    return <LoadingState message={`Searching for "${searchTerm}"...`} />;
  }

  // Show error state
  if (error) {
    return (
      <Box p={2} sx={{ 
        display: 'flex', 
        justifyContent: 'center', 
        alignItems: 'center', 
        minHeight: '70vh',
        textAlign: 'center'
      }}>
        <Typography 
          variant="h6" 
          sx={{ 
            color: 'var(--text-secondary)',
            maxWidth: '600px'
          }}
        >
          {error}
          <Typography 
            variant="body2" 
            sx={{ 
              color: 'var(--text-secondary)', 
              mt: 1,
              opacity: 0.8
            }}
          >
            {error.includes('API key') ? (
              <>
                Please make sure you have:
                <ol style={{ textAlign: 'left', marginTop: '10px' }}>
                  <li>Created a RapidAPI account</li>
                  <li>Subscribed to the YouTube v3 API</li>
                  <li>Added your API key to the .env file</li>
                  <li>Restarted the development server</li>
                </ol>
              </>
            ) : (
              'Please try again later or contact support if the problem persists.'
            )}
          </Typography>
        </Typography>
      </Box>
    );
  }

  // Show empty state if no videos
  if (!videos || videos.length === 0) {
    return (
      <Box p={2} sx={{ 
        display: 'flex', 
        justifyContent: 'center', 
        alignItems: 'center', 
        minHeight: '70vh',
        flexDirection: 'column',
        gap: 2
      }}>
        <Typography 
          variant="h6" 
          sx={{ 
            color: 'var(--text-secondary)',
            textAlign: 'center'
          }}
        >
          No videos found for "{searchTerm}"
        </Typography>
        <Typography 
          variant="body2" 
          sx={{ 
            color: 'var(--text-secondary)',
            opacity: 0.8,
            textAlign: 'center'
          }}
        >
          Try different keywords or check your spelling
        </Typography>
      </Box>
    );
  }

  // Show results with infinite scroll
  return (
    <Box 
      sx={{ 
        height: '90vh',
        backgroundColor: 'var(--secondary-bg)',
        backdropFilter: 'blur(5px)',
        borderRadius: '12px',
        border: '1px solid var(--border-color)',
      }}
    >
      <Box p={3}>
        <Typography 
          variant='h4' 
          fontWeight="500" 
          sx={{ 
            color: 'var(--text-primary)',
            mb: 2
          }}
        >
          Search Results for: <span style={{ color: 'var(--primary-color)' }}>{searchTerm}</span>
        </Typography>
        
        {/* Display active filters */}
        {activeFilters.length > 0 && (
          <Box sx={{ mb: 3, display: 'flex', flexWrap: 'wrap', gap: 1, alignItems: 'center' }}>
            <Stack direction="row" spacing={1} alignItems="center">
              <FilterAlt sx={{ color: 'var(--text-secondary)', fontSize: 20 }} />
              <Typography variant="body2" color="var(--text-secondary)">
                Filters:
              </Typography>
            </Stack>
            
            {activeFilters.map((filter) => (
              <Chip
                key={filter.key}
                label={filter.label}
                onDelete={() => removeFilter(filter.key)}
                size="small"
                sx={{
                  backgroundColor: 'rgba(255, 0, 0, 0.1)',
                  color: 'var(--text-primary)',
                  borderRadius: '4px',
                  '& .MuiChip-deleteIcon': {
                    color: 'var(--text-secondary)',
                    '&:hover': {
                      color: 'var(--primary-color)'
                    }
                  }
                }}
              />
            ))}
            
            <Chip
              label="Clear All"
              onClick={clearAllFilters}
              size="small"
              deleteIcon={<Clear />}
              onDelete={clearAllFilters}
              sx={{
                backgroundColor: 'rgba(255, 0, 0, 0.2)',
                color: 'var(--text-primary)',
                borderRadius: '4px',
                '& .MuiChip-deleteIcon': {
                  color: 'var(--primary-color)',
                }
              }}
            />
          </Box>
        )}
      </Box>

      <Videos 
        videos={videos}
        loading={loading}
        hasMore={hasMore}
        onLoadMore={fetchMoreData}
      />
    </Box>
  );
};

export default SearchFeed;
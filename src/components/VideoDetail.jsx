// Import necessary hooks from React
import { useState, useEffect, useRef } from 'react';
// Import routing components from react-router-dom
import { Link, useParams } from 'react-router-dom';
// Import the video player component
import ReactPlayer from 'react-player';
// Import Material-UI components for layout and styling
import { 
  Typography, 
  Box, 
  Stack, 
  Container, 
  Divider, 
  CircularProgress,
  Button
} from '@mui/material';
import { 
  CheckCircle,
  Subscriptions
} from '@mui/icons-material';
// Import our custom components and utilities
import SuggestedVideos from './SuggestedVideos';
import ShareButton from './common/ShareButton';
import { fetchFromAPI } from '../utils/fetchFromAPI';
import useWatchHistory from '../hooks/useWatchHistory';
import { useAuth } from '../contexts/AuthContext';
// Import the AddToPlaylistButton component
import AddToPlaylistButton from './common/AddToPlaylistButton';

const VideoDetail = () => {
  // State management using useState hook
  const [videoDetail, setVideoDetail] = useState(null);
  // videos will store the list of suggested videos
  const [videos, setVideos] = useState(null);
  // Subscription state
  const [subscribed, setSubscribed] = useState(false);
  
  // Reference to the video player
  const playerRef = useRef(null);
  
  // useParams hook from react-router to get the video ID from the URL
  const { id } = useParams();
  
  // Get watch history functions
  const { addToHistory } = useWatchHistory();
  
  // Get auth context
  const { currentUser, subscribeToChannel, isSubscribed } = useAuth();
  
  // useEffect hook runs when the component mounts or when 'id' changes
  useEffect(() => {
    const fetchVideoData = async () => {
      try {
        // Fetch details for the current video
        const videoData = await fetchFromAPI(`videos?part=snippet,statistics&id=${id}`);
        const videoDetails = videoData.items[0];
        setVideoDetail(videoDetails);
        
        // Add to watch history
        if (videoDetails) {
          addToHistory({
            id: { videoId: id },
            snippet: videoDetails.snippet,
            statistics: videoDetails.statistics
          });
          
          // Check if subscribed to this channel
          if (currentUser) {
            setSubscribed(isSubscribed(videoDetails.snippet.channelId));
          }
        }

        // Fetch related videos based on the current video ID
        const relatedData = await fetchFromAPI(`search?part=snippet&relatedToVideoId=${id}&type=video`);
        setVideos(relatedData.items);
      } catch (error) {
        console.error('Error fetching video data:', error);
      }
    };

    fetchVideoData();
  }, [id, addToHistory, currentUser, isSubscribed]);
  
  // Handle subscribe/unsubscribe
  const handleSubscribe = () => {
    if (!currentUser || !videoDetail) {
      return;
    }
    
    const channelId = videoDetail.snippet.channelId;
    const channelTitle = videoDetail.snippet.channelTitle;
    // Use a default thumbnail if not available
    const channelThumbnail = 'https://ui-avatars.com/api/?name=' + encodeURIComponent(channelTitle) + '&background=random&color=fff';
    
    const isNowSubscribed = subscribeToChannel(channelId, channelTitle, channelThumbnail);
    setSubscribed(isNowSubscribed);
  };

  // Show loading state if video details haven't loaded yet
  if (!videoDetail?.snippet) return (
    <Box sx={{ 
      display: 'flex',
      justifyContent: 'center',
      alignItems: 'center',
      height: '80vh',
      flexDirection: 'column',
      gap: 2
    }}>
      <CircularProgress sx={{ color: 'var(--primary-color)' }} />
      <Typography variant="body1" color="var(--text-secondary)">
        Loading video...
      </Typography>
    </Box>
  );

  // Destructure the video details for easier access
  const { 
    snippet: { title, channelId, channelTitle }, 
    statistics: { viewCount, likeCount } 
  } = videoDetail;

  return (
    <Container 
      maxWidth="xl"
      sx={{
        minHeight: '95vh',
        paddingTop: 2,
        paddingBottom: 4,
        overflow: 'hidden' // Prevent horizontal overflow
      }}
    >
      <Stack 
        direction={{ xs: 'column', md: 'row' }}
        spacing={3}
        sx={{
          background: 'rgba(26, 0, 0, 0.2)',
          backdropFilter: 'blur(5px)',
          borderRadius: '12px',
          border: '1px solid var(--border-color)',
          overflow: 'hidden',
        }}
      >
        <Box 
          sx={{ 
            width: { xs: '100%', md: '65%' }, // Reduced from 70% to 65% to give more space to sidebar
            padding: { xs: 2, md: 3 }
          }}
        >
          <Box sx={{ 
            width: '100%', 
            borderRadius: '8px',
            overflow: 'hidden',
            boxShadow: '0 4px 20px rgba(0, 0, 0, 0.3)'
          }}>
            <ReactPlayer 
              ref={playerRef}
              url={`https://www.youtube.com/watch?v=${id}`}
              className="react-player" 
              controls 
              width="100%"
              playing={true}
              config={{
                youtube: {
                  playerVars: {
                    modestbranding: 1,
                    rel: 0
                  }
                }
              }}
            />
          </Box>
          
          <Typography 
            color="var(--text-primary)" 
            variant="h5" 
            fontWeight="500" 
            sx={{ mt: 2, mb: 1 }}
          >
            {title}
          </Typography>
          
          <Divider sx={{ borderColor: 'var(--border-color)', my: 2 }} />
          
          <Stack 
            direction={{ xs: 'column', sm: 'row' }} 
            justifyContent="space-between" 
            sx={{ color: 'var(--text-primary)' }} 
            gap={2}
          >
            <Box sx={{ display: 'flex', flexDirection: 'column', gap: 1 }}>
              <Link to={`/channel/${channelId}`}>
                <Typography 
                  variant="subtitle1" 
                  sx={{ 
                    display: 'flex', 
                    alignItems: 'center',
                    color: 'var(--text-primary)',
                    '&:hover': { color: 'var(--primary-color)' },
                    transition: 'color 0.2s ease'
                  }}
                >
                  {channelTitle}
                  <CheckCircle sx={{ fontSize: '14px', color: 'var(--primary-color)', ml: '5px' }} />
                </Typography>
              </Link>
              
              <Button
                variant={subscribed ? "outlined" : "contained"}
                startIcon={<Subscriptions />}
                onClick={handleSubscribe}
                size="small"
                sx={{
                  alignSelf: 'flex-start',
                  backgroundColor: subscribed ? 'transparent' : 'var(--primary-color)',
                  borderColor: subscribed ? 'var(--primary-color)' : 'transparent',
                  color: subscribed ? 'var(--primary-color)' : 'white',
                  '&:hover': {
                    backgroundColor: subscribed ? 'rgba(255, 0, 0, 0.08)' : 'var(--primary-color-dark)',
                    borderColor: subscribed ? 'var(--primary-color)' : 'transparent',
                  }
                }}
              >
                {subscribed ? 'Subscribed' : 'Subscribe'}
              </Button>
            </Box>
            
            <Stack direction="row" gap="20px" alignItems="center">
              <Typography variant="body2" sx={{ color: 'var(--text-secondary)' }}>
                {parseInt(viewCount).toLocaleString()} views
              </Typography>
              <Typography variant="body2" sx={{ color: 'var(--text-secondary)' }}>
                {parseInt(likeCount).toLocaleString()} likes
              </Typography>
              
              {/* Share button */}
              <ShareButton videoId={id} title={title} />
              
              {/* Add to playlist button */}
              <AddToPlaylistButton video={videoDetail} />
            </Stack>
          </Stack>
        </Box>
        
        <Box 
          sx={{ 
            width: { xs: '100%', md: '35%' }, // Increased from 30% to 35%
            padding: 2,
            borderLeft: { md: `1px solid var(--border-color)` },
            backgroundColor: { xs: 'transparent', md: 'rgba(11, 0, 0, 0.3)' },
            height: { md: '100vh' },
            overflowY: 'auto',
            flexShrink: 0 // Prevent sidebar from shrinking
          }}
        >
          <Typography 
            variant="subtitle1" 
            fontWeight="500" 
            sx={{ mb: 2, color: 'var(--text-primary)' }}
          >
            Suggested <span style={{ color: 'var(--primary-color)' }}>Videos</span>
          </Typography>
          <SuggestedVideos videos={videos} />
        </Box>
      </Stack>
    </Container>
  );
};

export default VideoDetail;
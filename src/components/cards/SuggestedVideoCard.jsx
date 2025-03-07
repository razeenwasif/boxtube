import PropTypes from 'prop-types';
import { Link } from 'react-router-dom';
import { Typography, Box } from '@mui/material';
import { CheckCircle } from '@mui/icons-material';
import { cardStyles } from '../../styles/cardStyles';
import { demoThumbnailUrl, demoVideoUrl, demoVideoTitle, demoChannelTitle } from '../../utils/constants';

/**
 * SuggestedVideoCard Component
 * Displays a compact horizontal card for a suggested video
 */
const SuggestedVideoCard = ({ video }) => {
  const { id: { videoId }, snippet } = video;

  return (
    <Box sx={cardStyles.card}>
      <Link to={videoId ? `/video/${videoId}` : demoVideoUrl} style={cardStyles.link}>
        {/* Thumbnail Section */}
        <VideoThumbnail snippet={snippet} />
        
        {/* Video Details Section */}
        <VideoDetails snippet={snippet} />
      </Link>
    </Box>
  );
};

/**
 * VideoThumbnail Component
 * Displays the video thumbnail with optional duration overlay
 */
const VideoThumbnail = ({ snippet }) => (
  <Box 
    sx={{ 
      width: '168px',
      height: '94px',
      borderRadius: '8px 0 0 8px',
      overflow: 'hidden',
      flexShrink: 0,
      position: 'relative',
    }}
  >
    <img 
      src={snippet?.thumbnails?.medium?.url || demoThumbnailUrl} 
      alt={snippet?.title}
      style={{ 
        width: '100%', 
        height: '100%', 
        objectFit: 'cover',
        transition: 'transform 0.3s ease',
      }}
      className="thumbnail"
    />
    <DurationOverlay duration={snippet?.duration} />
  </Box>
);

/**
 * DurationOverlay Component
 * Displays video duration in the bottom right corner of the thumbnail
 */
const DurationOverlay = ({ duration }) => (
  <Box 
    sx={{ 
      position: 'absolute',
      bottom: 0,
      right: 0,
      backgroundColor: 'rgba(0, 0, 0, 0.7)',
      color: 'white',
      padding: '2px 4px',
      borderRadius: '2px',
      fontSize: '12px',
      margin: '4px',
    }}
  >
    {duration}
  </Box>
);

/**
 * VideoDetails Component
 * Displays video title and channel information
 */
const VideoDetails = ({ snippet }) => (
  <Box sx={{ p: 1.5, flex: 1 }}>
    <Typography 
      variant="subtitle2" 
      fontWeight="500" 
      sx={{
        ...cardStyles.title,
        display: '-webkit-box',
        WebkitLineClamp: 2,
        WebkitBoxOrient: 'vertical',
        overflow: 'hidden',
        lineHeight: 1.2,
        mb: 0.5,
      }}
    >
      {snippet?.title || demoVideoTitle}
    </Typography>
    
    <Typography 
      variant="caption" 
      sx={cardStyles.channelName}
    >
      {snippet?.channelTitle || demoChannelTitle}
      <CheckCircle sx={cardStyles.verifiedIcon} />
    </Typography>
  </Box>
);

// PropTypes definitions
SuggestedVideoCard.propTypes = {
  video: PropTypes.shape({
    id: PropTypes.shape({
      videoId: PropTypes.string
    }),
    snippet: PropTypes.shape({
      title: PropTypes.string,
      thumbnails: PropTypes.shape({
        medium: PropTypes.shape({
          url: PropTypes.string
        })
      }),
      channelTitle: PropTypes.string,
      duration: PropTypes.string
    })
  }).isRequired
};

VideoThumbnail.propTypes = {
  snippet: PropTypes.object.isRequired
};

DurationOverlay.propTypes = {
  duration: PropTypes.string
};

VideoDetails.propTypes = {
  snippet: PropTypes.object.isRequired
};

export default SuggestedVideoCard; 
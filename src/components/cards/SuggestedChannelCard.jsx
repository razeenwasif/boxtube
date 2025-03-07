import PropTypes from 'prop-types';
import { Link } from 'react-router-dom';
import { Typography, Box } from '@mui/material';
import { CheckCircle } from '@mui/icons-material';
import { cardStyles } from '../../styles/cardStyles';
import { demoThumbnailUrl, demoChannelTitle } from '../../utils/constants';

/**
 * SuggestedChannelCard Component
 * Displays a compact card for a suggested channel
 */
const SuggestedChannelCard = ({ channelDetail }) => (
  <Box sx={cardStyles.card}>
    <Link 
      to={`/channel/${channelDetail?.id?.channelId}`} 
      style={cardStyles.link}
    >
      <ChannelAvatar channelDetail={channelDetail} />
      <ChannelInfo channelDetail={channelDetail} />
    </Link>
  </Box>
);

/**
 * ChannelAvatar Component
 * Displays the channel's profile picture
 */
const ChannelAvatar = ({ channelDetail }) => (
  <Box 
    sx={{ 
      width: '50px',
      height: '50px',
      borderRadius: '50%',
      overflow: 'hidden',
      flexShrink: 0,
    }}
  >
    <img 
      src={channelDetail?.snippet?.thumbnails?.high?.url || demoThumbnailUrl} 
      alt={channelDetail?.snippet?.title}
      style={{ 
        width: '100%', 
        height: '100%', 
        objectFit: 'cover',
      }}
    />
  </Box>
);

/**
 * ChannelInfo Component
 * Displays channel name and subscriber count
 */
const ChannelInfo = ({ channelDetail }) => (
  <Box sx={{ ml: 2 }}>
    <Typography 
      variant="subtitle2" 
      fontWeight="500" 
      sx={cardStyles.title}
    >
      {channelDetail?.snippet?.title || demoChannelTitle}
      <CheckCircle sx={cardStyles.verifiedIcon} />
    </Typography>
    
    {channelDetail?.statistics?.subscriberCount && (
      <Typography variant="caption" sx={cardStyles.channelName}>
        {parseInt(channelDetail.statistics.subscriberCount).toLocaleString()} Subscribers
      </Typography>
    )}
  </Box>
);

// PropTypes definitions
SuggestedChannelCard.propTypes = {
  channelDetail: PropTypes.shape({
    id: PropTypes.shape({
      channelId: PropTypes.string
    }),
    snippet: PropTypes.shape({
      title: PropTypes.string,
      thumbnails: PropTypes.shape({
        high: PropTypes.shape({
          url: PropTypes.string
        })
      })
    }),
    statistics: PropTypes.shape({
      subscriberCount: PropTypes.string
    })
  }).isRequired
};

ChannelAvatar.propTypes = {
  channelDetail: PropTypes.object.isRequired
};

ChannelInfo.propTypes = {
  channelDetail: PropTypes.object.isRequired
};

export default SuggestedChannelCard; 
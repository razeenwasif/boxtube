import PropTypes from 'prop-types';
import { Box, Stack } from '@mui/material';
import LoadingState from './common/LoadingState';
import SuggestedVideoCard from './cards/SuggestedVideoCard';
import SuggestedChannelCard from './cards/SuggestedChannelCard';

/**
 * SuggestedVideos Component
 * Displays a vertical list of suggested videos and channels
 * @param {Object[]} videos - Array of video and channel objects from YouTube API
 */
const SuggestedVideos = ({ videos }) => {
  if (!videos?.length) {
    return <LoadingState message="Loading suggestions..." />;
  }

  return (
    <Stack 
      direction="column"
      spacing={2}
    >
      {videos.map((item, idx) => (
        <Box key={idx}>
          {item.id.videoId && <SuggestedVideoCard video={item} />}
          {item.id.channelId && <SuggestedChannelCard channelDetail={item} />}
        </Box>
      ))}
    </Stack>
  );
};

SuggestedVideos.propTypes = {
  videos: PropTypes.arrayOf(
    PropTypes.shape({
      id: PropTypes.shape({
        videoId: PropTypes.string,
        channelId: PropTypes.string
      }),
      snippet: PropTypes.object
    })
  )
};

export default SuggestedVideos; 
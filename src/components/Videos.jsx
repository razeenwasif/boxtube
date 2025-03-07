import { Stack, Box, Typography, CircularProgress } from '@mui/material';
import { VideoCard, ChannelCard } from './';

const Videos = ({ videos, direction, loading, hasMore, onLoadMore }) => {
  if (!videos?.length) return (
    <Box sx={{ 
      display: 'flex', 
      justifyContent: 'center', 
      alignItems: 'center', 
      height: '50vh',
      flexDirection: 'column',
      gap: 2
    }}>
      <CircularProgress sx={{ color: 'var(--primary-color)' }} />
      <Typography variant="body1" color="var(--text-secondary)">
        Loading videos...
      </Typography>
    </Box>
  );

  return (
    <Box sx={{ 
      padding: { xs: 1, sm: 2 },
      overflow: 'hidden', // Prevent horizontal overflow
      width: '100%'
    }}>
      <Stack 
        direction={direction || "row"} 
        flexWrap="wrap" 
        sx={{
          display: 'grid',
          gridTemplateColumns: {
            xs: 'repeat(1, 1fr)',
            sm: 'repeat(2, 1fr)',
            md: 'repeat(3, 1fr)',
            lg: 'repeat(3, 1fr)'
          },
          gap: 3,
          width: '100%'
        }}
      >
        {videos.map((item, idx) => (
          // if the item has an id and its a video id, the first result will be the video or else the profile channel
          <Box key={idx} sx={{ width: '100%' }}>
            {item.id.videoId && <VideoCard video={item} />}
            {item.id.channelId && <ChannelCard channelDetail={item} />}
          </Box>
        ))}
      </Stack>
      
      {/* Loading indicator for infinite scroll */}
      {loading && hasMore && (
        <Box sx={{ 
          display: 'flex', 
          justifyContent: 'center', 
          padding: 3 
        }}>
          <CircularProgress size={30} sx={{ color: 'var(--primary-color)' }} />
        </Box>
      )}
      
      {/* End of content message */}
      {!loading && !hasMore && videos.length > 0 && (
        <Typography 
          variant="body2" 
          align="center" 
          sx={{ 
            padding: 3, 
            color: 'var(--text-secondary)' 
          }}
        >
          No more videos to load
        </Typography>
      )}
    </Box>
  );
};

export default Videos;
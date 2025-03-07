import { useState } from 'react';
import { Box, Stack, Typography, Container } from '@mui/material';
import { SideBar, Videos } from './';
import useYoutubeApi from '../hooks/useYoutubeApi';

// This is the Side Bar and its categories

const Feed = () => {
  const [selectedCategory, setSelectedCategory] = useState('New');
  const { 
    data: videos, 
    loading, 
    error, 
    hasMore, 
    fetchMoreData 
  } = useYoutubeApi(
    'search',
    {
      part: 'snippet',
      q: selectedCategory,
      maxResults: 50 // Increased from 20 to 50 to show more videos
    }
  );

  return (
    <Container 
      maxWidth="xl" 
      disableGutters
      sx={{
        background: 'var(--background-color)',
        minHeight: '100vh',
        overflow: 'hidden', // Prevent horizontal overflow
      }}
    >
      <Stack 
        direction={{ xs: "column", md: "row" }}
        spacing={2}
        sx={{ 
          padding: { xs: 1, sm: 2 },
        }}
      >
        <Box 
          sx={{ 
            height: { xs: 'auto', md: '92vh' }, 
            width: { xs: '100%', md: '280px' }, // Increased from 240px to 280px
            position: { xs: 'static', md: 'sticky' },
            top: { md: '70px' },
            flexShrink: 0, // Prevent sidebar from shrinking
          }}
        > 
          <SideBar 
            selectedCategory={selectedCategory}
            setSelectedCategory={setSelectedCategory}
          />
          
          <Typography 
            className='copyright' 
            variant='caption' 
            sx={{ 
              mt: 2, 
              color: 'var(--text-secondary)',
              display: 'block',
              textAlign: 'center',
              padding: '0 16px'
            }}
          > 
            © 2023 BoxTube
          </Typography>
        </Box>

        <Box 
          sx={{ 
            height: '90vh',
            flex: 1,
            borderRadius: '12px',
            background: 'var(--secondary-bg)',
            backdropFilter: 'blur(5px)',
            border: '1px solid var(--border-color)',
            overflow: 'hidden', // Prevent content overflow
          }}
        >
          <Box p={3}>
            <Typography 
              variant='h5' 
              fontWeight="500" 
              sx={{ 
                color: 'var(--text-primary)',
                borderBottom: '1px solid var(--border-color)',
                paddingBottom: '12px',
              }}
            >
              {selectedCategory} <span style={{ color: 'var(--primary-color)' }}>videos</span>
            </Typography>
          </Box>

          {error ? (
            <Typography 
              variant="body1" 
              sx={{ 
                color: 'var(--text-secondary)',
                textAlign: 'center',
                mt: 4
              }}
            >
              {error}
            </Typography>
          ) : (
            <Videos 
              videos={videos}
              loading={loading}
              hasMore={hasMore}
              onLoadMore={fetchMoreData}
            />
          )}
        </Box>
      </Stack>
    </Container>
  );
};

export default Feed;
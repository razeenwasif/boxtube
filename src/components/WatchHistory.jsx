import { useState } from 'react';
import { 
  Box, 
  Typography, 
  Container, 
  Stack, 
  Button, 
  Divider,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  Alert
} from '@mui/material';
import { Delete, History } from '@mui/icons-material';
import { Videos } from './';
import useWatchHistory from '../hooks/useWatchHistory';

const WatchHistory = () => {
  const { watchHistory, clearHistory } = useWatchHistory();
  const [confirmOpen, setConfirmOpen] = useState(false);

  const handleClearHistory = () => {
    setConfirmOpen(true);
  };

  const confirmClearHistory = () => {
    clearHistory();
    setConfirmOpen(false);
  };

  const cancelClearHistory = () => {
    setConfirmOpen(false);
  };

  return (
    <Container maxWidth="xl" sx={{ minHeight: '90vh', paddingY: 3 }}>
      <Box sx={{ 
        background: 'rgba(26, 0, 0, 0.2)',
        backdropFilter: 'blur(5px)',
        borderRadius: '12px',
        border: '1px solid var(--border-color)',
        padding: 3,
        mb: 3
      }}>
        <Stack 
          direction={{ xs: 'column', sm: 'row' }} 
          justifyContent="space-between" 
          alignItems={{ xs: 'flex-start', sm: 'center' }}
          spacing={2}
          mb={2}
        >
          <Box sx={{ display: 'flex', alignItems: 'center', gap: 1 }}>
            <History sx={{ color: 'var(--primary-color)', fontSize: 28 }} />
            <Typography variant="h4" fontWeight="bold" color="var(--text-primary)">
              Watch History
            </Typography>
          </Box>
          
          <Button 
            variant="outlined" 
            color="error" 
            startIcon={<Delete />}
            onClick={handleClearHistory}
            disabled={!watchHistory.length}
            sx={{
              borderColor: 'var(--border-color)',
              '&:hover': {
                borderColor: 'var(--primary-color)',
                backgroundColor: 'rgba(255, 0, 0, 0.08)'
              }
            }}
          >
            Clear History
          </Button>
        </Stack>
        
        <Divider sx={{ borderColor: 'var(--border-color)', mb: 3 }} />
        
        {watchHistory.length > 0 ? (
          <Videos videos={watchHistory} />
        ) : (
          <Box 
            sx={{ 
              display: 'flex', 
              flexDirection: 'column', 
              alignItems: 'center', 
              justifyContent: 'center',
              minHeight: '50vh',
              gap: 2
            }}
          >
            <History sx={{ fontSize: 60, color: 'var(--text-secondary)' }} />
            <Typography variant="h6" color="var(--text-secondary)" textAlign="center">
              Your watch history is empty
            </Typography>
            <Typography variant="body2" color="var(--text-secondary)" textAlign="center">
              Videos you watch will appear here
            </Typography>
          </Box>
        )}
      </Box>
      
      {/* Confirmation Dialog */}
      <Dialog
        open={confirmOpen}
        onClose={cancelClearHistory}
        PaperProps={{
          sx: {
            backgroundColor: 'var(--card-bg)',
            border: '1px solid var(--border-color)',
            boxShadow: 'var(--card-hover-shadow)',
          }
        }}
      >
        <DialogTitle sx={{ color: 'var(--text-primary)' }}>
          Clear Watch History?
        </DialogTitle>
        <DialogContent>
          <Alert severity="warning" sx={{ mb: 2 }}>
            This action cannot be undone.
          </Alert>
          <Typography variant="body1" color="var(--text-secondary)">
            Are you sure you want to clear your entire watch history?
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button 
            onClick={cancelClearHistory}
            sx={{ color: 'var(--text-secondary)' }}
          >
            Cancel
          </Button>
          <Button 
            onClick={confirmClearHistory}
            color="error"
            variant="contained"
          >
            Clear History
          </Button>
        </DialogActions>
      </Dialog>
    </Container>
  );
};

export default WatchHistory; 